# SPDX-License-Identifier: GPL-2.0-only
# Included after rules.mk, only by toolchain/auxiliary makefiles.

ifeq ($(strip $(AUX_PROFILE)),)
  $(error AUX_PROFILE is required)
endif

# Profile: <gnu-triple>__<isa>__<abi>__gcc-<version>
AUX_COMPONENTS := $(subst __, ,$(AUX_PROFILE))
ifneq ($(words $(AUX_COMPONENTS)),4)
  $(error Invalid AUX_PROFILE '$(AUX_PROFILE)')
endif
AUX_TARGET := $(word 1,$(AUX_COMPONENTS))
AUX_CPU_TYPE := $(word 2,$(AUX_COMPONENTS))
AUX_ABI := $(word 3,$(AUX_COMPONENTS))
AUX_GCC_VERSION := $(patsubst gcc-%,%,$(word 4,$(AUX_COMPONENTS)))

ifneq ($(AUX_TARGET),riscv64-unknown-elf)
  $(error Unsupported AUX_TARGET '$(AUX_TARGET)')
endif
ifeq ($(filter rv32%,$(AUX_CPU_TYPE)),)
  $(error Unsupported auxiliary ISA '$(AUX_CPU_TYPE)')
endif
ifneq ($(AUX_ABI),ilp32)
  $(error Unsupported auxiliary ABI '$(AUX_ABI)')
endif
ifeq ($(filter 13.4.0 14.4.0 15.3.0,$(AUX_GCC_VERSION)),)
  $(error Unsupported auxiliary GCC version '$(AUX_GCC_VERSION)')
endif

override BUILD_DIR_TOOLCHAIN := $(BUILD_DIR_BASE)/toolchain-$(AUX_PROFILE)
override TOOLCHAIN_DIR := $(TOPDIR)/staging_dir/toolchain-$(AUX_PROFILE)
