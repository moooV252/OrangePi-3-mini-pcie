#include SOC_HEADER

#include <asm/system.h>

	.section .rodata
	.asciz "Allwinner H6 EL2 shim: SP_EL1 initialized"
	.asciz "Allwinner H6 EL2 shim: C code uses general registers only"
	.text

#ifdef DIAGNOSTIC_NO_STAGE2
	.section .rodata
	.asciz "Allwinner H6 EL2 diagnostic: stage-2 disabled"
	.text
#endif
#ifdef DIAGNOSTIC_NO_PSCI_TRAP
	.section .rodata
	.asciz "Allwinner H6 EL2 diagnostic: PSCI trap disabled"
	.text
#endif
#ifdef DIAGNOSTIC_SKIP_INIT
	.section .rodata
	.asciz "Allwinner H6 EL2 diagnostic: shim init skipped"
	.text
#endif
#ifdef DIAGNOSTIC_TABLES_ONLY
	.section .rodata
	.asciz "Allwinner H6 EL2 diagnostic: tables built, registers untouched"
	.text
#endif

.globl _start

_start:
	/*
	 * U-Boot enters the shim immediately before Linux:
	 *   x0 = Linux DTB
	 *   x1 = Linux entry point
	 *
	 * Keep both values in callee-saved registers while init() creates the
	 * stage-2 mappings. This avoids running U-Boot itself at EL1.
	 */
	mov x19, x1
	mov x20, x0

	mov x1, #1
	msr spsel, x1
	ldr x1, =stack_generic
	mov sp, x1

	ldr x1, =vectors
	msr vbar_el2, x1

#ifdef DIAGNOSTIC_SKIP_INIT
	mov x0, xzr
#else
	bl init
#endif

	cbz x0, jump_to_el1
	/*
	 * If shim initialization failed, preserve the known-good behavior:
	 * enter Linux directly at EL2 instead of leaving the board unbootable.
	 */
fail:
	mov x0, x20
	br x19

jump_to_el1:
	/* Initialize Generic Timers */
	mrs	x6, cnthctl_el2
	/* Enable EL1 access to timers */
	orr	x6, x6, #(CNTHCTL_EL2_EL1PCEN_EN |\
		CNTHCTL_EL2_EL1PCTEN_EN)
	msr	cnthctl_el2, x6
	msr	cntvoff_el2, xzr

	/* Initilize MPID/MPIDR registers */
	mrs	x6, midr_el1
	msr	vpidr_el2, x6
	mrs	x6, mpidr_el1
	msr	vmpidr_el2, x6

	/* Disable coprocessor traps */
	mov	x6, #CPTR_EL2_RES1
	msr	cptr_el2, x6		/* Disable coprocessor traps to EL2 */
	msr	hstr_el2, xzr		/* Disable coprocessor traps to EL2 */
	mov	x6, #CPACR_EL1_FPEN_EN
	msr	cpacr_el1, x6		/* Enable FP/SIMD at EL1 */

	/* SCTLR_EL1 initialization
	 *
	 * setting RES1 bits (29,28,23,22,20,11) to 1
	 * and RES0 bits (31,30,27,21,17,13,10,6) +
	 * UCI,EE,EOE,WXN,nTWE,nTWI,UCT,DZE,I,UMA,SED,ITD,
	 * CP15BEN,SA0,SA,C,A,M to 0
	 */
	ldr	x6, =(SCTLR_EL1_RES1 | SCTLR_EL1_UCI_DIS |\
			SCTLR_EL1_EE_LE | SCTLR_EL1_WXN_DIS |\
			SCTLR_EL1_NTWE_DIS | SCTLR_EL1_NTWI_DIS |\
			SCTLR_EL1_UCT_DIS | SCTLR_EL1_DZE_DIS |\
			SCTLR_EL1_ICACHE_DIS | SCTLR_EL1_UMA_DIS |\
			SCTLR_EL1_SED_EN | SCTLR_EL1_ITD_EN |\
			SCTLR_EL1_CP15BEN_DIS | SCTLR_EL1_SA0_DIS |\
			SCTLR_EL1_SA_DIS | SCTLR_EL1_DCACHE_DIS |\
			SCTLR_EL1_ALIGN_DIS | SCTLR_EL1_MMU_DIS)
	msr	sctlr_el1, x6

	/* Linux is entered in EL1h and therefore uses SP_EL1. Match U-Boot's
	 * armv8_switch_to_el1_m sequence by migrating the known-good stack. */
	mov	x6, sp
	msr	sp_el1, x6
	mrs	x6, vbar_el2
	msr	vbar_el1, x6		/* Migrate VBAR */

	/* Initialize HCR_EL2. The diagnostics can independently leave stage-2
	 * translation disabled and allow SMC/PSCI calls to go directly to TF-A. */
#ifdef DIAGNOSTIC_NO_PSCI_TRAP
	ldr	x6, =(HCR_EL2_RW_AARCH64 | HCR_EL2_HCD_DIS)
#elif defined(DIAGNOSTIC_NO_STAGE2)
	ldr	x6, =(HCR_EL2_RW_AARCH64 | HCR_EL2_HCD_DIS | HCR_EL2_TSC_ENABLE)
#else
	ldr	x6, =(HCR_EL2_RW_AARCH64 | HCR_EL2_HCD_DIS | HCR_EL2_TSC_ENABLE | HCR_EL2_VM_ENABLE)
#endif
	/*
	 * init() populated the stage-2 tables with the MMU and caches off.
	 * Make the table writes and EL2 control-register writes globally
	 * visible before entering Linux.  ERET is not guaranteed to provide
	 * this synchronization on every implementation.
	 */
	dsb	sy
	isb
	msr	hcr_el2, x6
	isb

	/* Return to the EL1_SP1 mode from EL2 */
	ldr	x6, =(SPSR_EL_DEBUG_MASK | SPSR_EL_SERR_MASK |\
			SPSR_EL_IRQ_MASK | SPSR_EL_FIQ_MASK |\
			SPSR_EL_M_AARCH64 | SPSR_EL_M_EL1H)
	msr	spsr_el2, x6
	msr     elr_el2, x19
	mov	x0, x20
	/* The arm64 boot protocol requires x1, x2 and x3 to be zero. */
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	eret

.global _secondary_start
_secondary_start:
	mov x1, #1
	msr spsel, x1

	mrs x1, mpidr_el1
	and x1, x1, #0x00ffffff
	cmp x1, #0
	beq 1f
	cmp x1, #1
	beq 2f
	cmp x1, #2
	beq 3f
	cmp x1, #3
	beq 4f
spin:	b spin
1:	ldr x1, =stack_generic
	b 6f
2:	ldr x1, =stack_generic_core1
	b 6f
3:	ldr x1, =stack_generic_core2
	b 6f
4:	ldr x1, =stack_generic_core3
	b 6f
6:	mov sp, x1

	ldr x1, =vectors
	msr vbar_el2, x1

	stp x0, x2, [sp, #-16]!
	bl secondary_init
	cbz x0, spin
	mov x19, x0
	ldp x0, x2, [sp], #16
	mov x20, x0
	b jump_to_el1
