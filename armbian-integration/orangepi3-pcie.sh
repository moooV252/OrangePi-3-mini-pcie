#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Enable the wrapped H6 PCIe root complex on the original Orange Pi 3.

function extension_prepare_config__orangepi3_pcie() {
	if [[ "${BOARD}" != "orangepi3" || "${BRANCH}" != "current" ]]; then
		exit_with_error "orangepi3-pcie supports only BOARD=orangepi3 BRANCH=current"
	fi

	# This port and its recorded live controls are tied to Linux 6.18.41.
	# Pin the immutable stable commit so linux-6.18.y advancing cannot turn a
	# one-variable hardware experiment into an unintentional kernel upgrade.
	declare -g KERNELBRANCH="commit:2fe596715f840d053aed5cee5455f701bdcd2b50"
	if [[ "${ORANGEPI3_PCIE_DISABLE_PROBE:-no}" != "no" &&
		"${ORANGEPI3_PCIE_DISABLE_PROBE:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_DISABLE_PROBE must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" != "no" &&
		"${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_DISABLE_STAGE2 must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}" != "no" &&
		"${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_DISABLE_PSCI_TRAP must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_SINGLE_CORE:-no}" != "no" &&
		"${ORANGEPI3_PCIE_SINGLE_CORE:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_SINGLE_CORE must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_UBOOT_EL1_CONTROL:-no}" != "no" &&
		"${ORANGEPI3_PCIE_UBOOT_EL1_CONTROL:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_UBOOT_EL1_CONTROL must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_SKIP_SHIM_INIT:-no}" != "no" &&
		"${ORANGEPI3_PCIE_SKIP_SHIM_INIT:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_SKIP_SHIM_INIT must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_TABLES_ONLY:-no}" != "no" &&
		"${ORANGEPI3_PCIE_TABLES_ONLY:-no}" != "yes" ]]; then
		exit_with_error "ORANGEPI3_PCIE_TABLES_ONLY must be yes or no"
	fi
	if [[ "${ORANGEPI3_PCIE_DISABLE_PROBE:-no}" == "yes" &&
		"${ORANGEPI3_PCIE_EL2_SHIM:-yes}" != "yes" &&
		"${ORANGEPI3_PCIE_UBOOT_EL1_CONTROL:-no}" != "yes" ]]; then
		exit_with_error "The no-probe diagnostic requires ORANGEPI3_PCIE_EL2_SHIM=yes"
	fi
	if [[ "${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" == "yes" &&
		"${ORANGEPI3_PCIE_DISABLE_PROBE:-no}" != "yes" ]]; then
		exit_with_error "The no-stage2 diagnostic requires ORANGEPI3_PCIE_DISABLE_PROBE=yes"
	fi
	if [[ "${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}" == "yes" &&
		( "${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" != "yes" ||
		"${ORANGEPI3_PCIE_SINGLE_CORE:-no}" != "yes" ) ]]; then
		exit_with_error "The direct-PSCI diagnostic requires no-stage2 and single-core modes"
	fi
	if [[ "${ORANGEPI3_PCIE_UBOOT_EL1_CONTROL:-no}" == "yes" &&
		( "${ORANGEPI3_PCIE_EL2_SHIM:-yes}" != "no" ||
		"${ORANGEPI3_PCIE_DISABLE_PROBE:-no}" != "yes" ) ]]; then
		exit_with_error "The U-Boot EL1 control requires shim=no and PCIe probe disabled"
	fi
	if [[ "${ORANGEPI3_PCIE_SKIP_SHIM_INIT:-no}" == "yes" &&
		( "${ORANGEPI3_PCIE_EL2_SHIM:-yes}" != "yes" ||
		"${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" != "yes" ||
		"${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}" != "yes" ||
		"${ORANGEPI3_PCIE_SINGLE_CORE:-no}" != "yes" ) ]]; then
		exit_with_error "The skip-init diagnostic requires shim, no-stage2, direct-PSCI, and single-core modes"
	fi
	if [[ "${ORANGEPI3_PCIE_TABLES_ONLY:-no}" == "yes" &&
		( "${ORANGEPI3_PCIE_EL2_SHIM:-yes}" != "yes" ||
		"${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" != "yes" ||
		"${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}" != "yes" ||
		"${ORANGEPI3_PCIE_SINGLE_CORE:-no}" != "yes" ||
		"${ORANGEPI3_PCIE_SKIP_SHIM_INIT:-no}" != "no" ) ]]; then
		exit_with_error "The tables-only diagnostic requires shim, no-stage2, direct-PSCI, single-core, and skip-init=no modes"
	fi

	# The optional patch deliberately disables the DT node while retaining the
	# complete EL2 handoff. This produces a binary-isolation image for boards
	# without a serial console: if it boots, the first paged PCIe access is the
	# failing path. Remove the generated patch on every normal build so a prior
	# diagnostic invocation cannot contaminate a functional image.
	declare diagnostic_patch_source="${USERPATCHES_PATH}/sources/orangepi3-pcie-diagnostics/0002-disable-pcie-probe.patch"
	declare diagnostic_patch_active="${USERPATCHES_PATH}/kernel/archive/sunxi-6.18/9999-orangepi3-disable-pcie-probe-diagnostic.patch"
	declare single_core_patch_source="${USERPATCHES_PATH}/sources/orangepi3-pcie-diagnostics/0003-disable-secondary-cpus.patch"
	declare single_core_patch_active="${USERPATCHES_PATH}/kernel/archive/sunxi-6.18/9998-orangepi3-disable-secondary-cpus-diagnostic.patch"
	if [[ "${ORANGEPI3_PCIE_DISABLE_PROBE:-no}" == "yes" ]]; then
		[[ -f "${diagnostic_patch_source}" ]] ||
			exit_with_error "Missing Orange Pi 3 no-probe diagnostic patch" "${diagnostic_patch_source}"
		run_host_command_logged install -m 0644 "${diagnostic_patch_source}" "${diagnostic_patch_active}"
		display_alert "Orange Pi 3 PCIe probe disabled" "EL2-shim boot isolation image" "wrn"
	else
		run_host_command_logged rm -f -- "${diagnostic_patch_active}"
	fi
	if [[ "${ORANGEPI3_PCIE_SINGLE_CORE:-no}" == "yes" ]]; then
		[[ -f "${single_core_patch_source}" ]] ||
			exit_with_error "Missing Orange Pi 3 single-core diagnostic patch" "${single_core_patch_source}"
		run_host_command_logged install -m 0644 "${single_core_patch_source}" "${single_core_patch_active}"
		display_alert "Orange Pi 3 secondary CPUs disabled" "primary EL1 handoff isolation" "wrn"
	else
		run_host_command_logged rm -f -- "${single_core_patch_active}"
	fi

	# Include the vendored EL2 source revision in U-Boot artifact cache keys.
	UBOOT_HASH_EXTRA="${UBOOT_HASH_EXTRA:-}:orangepi3-pcie-aw-el2-beeae4c-v17-split-msi-target-${ORANGEPI3_PCIE_EL2_SHIM:-yes}-${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}-${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}-${ORANGEPI3_PCIE_UBOOT_EL1_CONTROL:-no}-${ORANGEPI3_PCIE_SKIP_SHIM_INIT:-no}-${ORANGEPI3_PCIE_TABLES_ONLY:-no}"
}

function extension_finish_config__orangepi3_pcie_set_tf_a_bl33() {
	# Keep the proven TF-A -> U-Boot handoff. This is explicit because
	# TF-A's build system does not track a changed PRELOADED_BL33_BASE in
	# existing objects, and an earlier experimental build used 0x40010000.
	declare -g ATF_TARGET_MAP="PLAT=${ATF_PLAT} DEBUG=1 PRELOADED_BL33_BASE=0x4a000000 bl31;;build/${ATF_PLAT}/debug/bl31.bin"
	CLEAN_LEVEL="${CLEAN_LEVEL:-},make-atf"
}

function custom_kernel_config__orangepi3_pcie() {
	opts_y+=("PCIE_SUNXI_WRAPPED" "PCI_MSI")
}

function pre_config_uboot_target__orangepi3_pcie_build_el2_shim() {
	if [[ "${ORANGEPI3_PCIE_EL2_SHIM:-yes}" != "yes" ]]; then
		display_alert "Orange Pi 3 PCIe EL2 shim disabled" "boot-control build" "wrn"
		return 0
	fi

	declare hyp_source="${USERPATCHES_PATH}/sources/aw-el2-barebone"
	declare hyp_build="${WORKDIR}/orangepi3-pcie-aw-el2"

	[[ -f "${hyp_source}/Makefile" && -f "${hyp_source}/include/h6.h" ]] ||
		exit_with_error "Missing vendored Orange Pi 3 EL2 shim source" "${hyp_source}"

	# WORKDIR is Armbian's disposable build area. Recreate this one exact
	# subdirectory so repeat builds cannot reuse stale objects.
	[[ "${hyp_build}" == "${WORKDIR}/orangepi3-pcie-aw-el2" ]] ||
		exit_with_error "Refusing unsafe EL2 build directory" "${hyp_build}"
	run_host_command_logged rm -rf -- "${hyp_build}"
	run_host_command_logged mkdir -p "${hyp_build}"
	run_host_command_logged cp -a "${hyp_source}/." "${hyp_build}/"

	declare diagnostic_no_stage2=0
	declare diagnostic_no_psci_trap=0
	declare diagnostic_skip_init=0
	declare diagnostic_tables_only=0
	if [[ "${ORANGEPI3_PCIE_DISABLE_STAGE2:-no}" == "yes" ]]; then
		diagnostic_no_stage2=1
		display_alert "Building Orange Pi 3 EL2 diagnostic" "stage-2 translation disabled" "wrn"
	else
		display_alert "Building Orange Pi 3 PCIe EL2 shim" "load address 0x40010000" "info"
	fi
	if [[ "${ORANGEPI3_PCIE_DISABLE_PSCI_TRAP:-no}" == "yes" ]]; then
		diagnostic_no_psci_trap=1
		display_alert "Building Orange Pi 3 EL2 diagnostic" "PSCI trapping disabled" "wrn"
	fi
	if [[ "${ORANGEPI3_PCIE_SKIP_SHIM_INIT:-no}" == "yes" ]]; then
		diagnostic_skip_init=1
		display_alert "Building Orange Pi 3 EL2 diagnostic" "shim init skipped" "wrn"
	fi
	if [[ "${ORANGEPI3_PCIE_TABLES_ONLY:-no}" == "yes" ]]; then
		diagnostic_tables_only=1
		display_alert "Building Orange Pi 3 EL2 diagnostic" "tables built, translation registers untouched" "wrn"
	fi
	run_host_command_logged make -C "${hyp_build}" \
		CROSS_COMPILE="${UBOOT_COMPILER}" \
		DIAGNOSTIC_NO_STAGE2="${diagnostic_no_stage2}" \
		DIAGNOSTIC_NO_PSCI_TRAP="${diagnostic_no_psci_trap}" \
		DIAGNOSTIC_SKIP_INIT="${diagnostic_skip_init}" \
		DIAGNOSTIC_TABLES_ONLY="${diagnostic_tables_only}" clean all
	# EL2 enters this C code before enabling FP/SIMD access. Reject a shim if
	# the compiler ever emits vector or floating-point register operands.
	if "${UBOOT_COMPILER}objdump" --no-show-raw-insn -d "${hyp_build}/el2-bb.elf" |
		grep -Eq '(^|[[:space:],])([bhsdqv][0-9]+)([[:space:],.]|$)'; then
		exit_with_error "Orange Pi 3 EL2 shim unexpectedly uses FP/SIMD registers"
	fi
	run_host_command_logged cp -v "${hyp_build}/el2-bb.bin" ./hyp.bin
}

function post_config_uboot_target__orangepi3_pcie_enable_el2_shim() {
	if [[ "${ORANGEPI3_PCIE_UBOOT_EL1_CONTROL:-no}" == "yes" ]]; then
		display_alert "Enabling canonical U-Boot EL1 handoff" "shim-free boot isolation" "wrn"
		run_host_command_logged ./scripts/config --disable CONFIG_SUNXI_H6_EL2_HYP
		run_host_command_logged ./scripts/config --enable CONFIG_ARMV8_SWITCH_TO_EL1
		run_host_command_logged ./scripts/config --set-str CONFIG_IDENT_STRING \
			" OrangePi3-U-Boot-EL1-control"
		return 0
	fi
	if [[ "${ORANGEPI3_PCIE_EL2_SHIM:-yes}" != "yes" ]]; then
		run_host_command_logged ./scripts/config --disable CONFIG_ARMV8_SWITCH_TO_EL1
		run_host_command_logged ./scripts/config --disable CONFIG_SUNXI_H6_EL2_HYP
		return 0
	fi

	display_alert "Enabling Orange Pi 3 PCIe EL2 handoff" "TF-A -> U-Boot -> hyp.bin -> Linux" "info"
	run_host_command_logged ./scripts/config --disable CONFIG_ARMV8_SWITCH_TO_EL1
	run_host_command_logged ./scripts/config --enable CONFIG_SUNXI_H6_EL2_HYP
}
