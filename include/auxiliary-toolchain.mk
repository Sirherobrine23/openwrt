# SPDX-License-Identifier: GPL-2.0-only
#
# Secondary, package-selected bare-metal compiler. Do not override TARGET_*:
# those variables always describe the Linux target of the OpenWrt image.
#
# Profile naming uses '__' separators because a RISC-V -march value may
# contain single underscores (e.g. rv32im_zicsr_zifencei).

ifneq ($(strip $(PKG_TOOLCHAIN_ARCH)$(PKG_TOOLCHAIN_TARGET)),)

  ifeq ($(strip $(PKG_TOOLCHAIN_TARGET)),)
    ifeq ($(strip $(PKG_TOOLCHAIN_ARCH)),riscv64)
      PKG_TOOLCHAIN_TARGET:=riscv64-unknown-elf
    endif
  endif
  ifeq ($(strip $(PKG_TOOLCHAIN_ARCH)),)
    PKG_TOOLCHAIN_ARCH:=$(firstword $(subst -, ,$(PKG_TOOLCHAIN_TARGET)))
  endif

  PKG_TOOLCHAIN_CPU_TYPE ?= rv32imac
  PKG_TOOLCHAIN_ABI ?= ilp32
  PKG_TOOLCHAIN_LIBC ?= none
  PKG_TOOLCHAIN_GCC_VERSION ?= 14.4.0

  ifneq ($(PKG_TOOLCHAIN_ARCH):$(PKG_TOOLCHAIN_TARGET),riscv64:riscv64-unknown-elf)
    $(error Unsupported auxiliary toolchain $(PKG_TOOLCHAIN_ARCH):$(PKG_TOOLCHAIN_TARGET))
  endif
  ifeq ($(filter rv32%,$(PKG_TOOLCHAIN_CPU_TYPE)),)
    $(error Unsupported PKG_TOOLCHAIN_CPU_TYPE '$(PKG_TOOLCHAIN_CPU_TYPE)' (expected rv32 ISA))
  endif
  ifneq ($(PKG_TOOLCHAIN_ABI),ilp32)
    $(error Unsupported PKG_TOOLCHAIN_ABI '$(PKG_TOOLCHAIN_ABI)' (expected ilp32))
  endif
  ifneq ($(PKG_TOOLCHAIN_LIBC),none)
    $(error Unsupported PKG_TOOLCHAIN_LIBC '$(PKG_TOOLCHAIN_LIBC)' (bare-metal only))
  endif
  ifeq ($(filter 13.4.0 14.4.0 15.3.0,$(PKG_TOOLCHAIN_GCC_VERSION)),)
    $(error Unsupported PKG_TOOLCHAIN_GCC_VERSION '$(PKG_TOOLCHAIN_GCC_VERSION)')
  endif
  # Avoid ambiguous profiles or invalid make target names.
  ifneq ($(words $(subst __, ,$(PKG_TOOLCHAIN_CPU_TYPE))),1)
    $(error PKG_TOOLCHAIN_CPU_TYPE must not contain '__')
  endif

  PKG_TOOLCHAIN_PROFILE := $(PKG_TOOLCHAIN_TARGET)__$(PKG_TOOLCHAIN_CPU_TYPE)__$(PKG_TOOLCHAIN_ABI)__gcc-$(PKG_TOOLCHAIN_GCC_VERSION)
  PKG_TOOLCHAIN_DIR := $(TOPDIR)/staging_dir/toolchain-$(PKG_TOOLCHAIN_PROFILE)
  PKG_TOOLCHAIN_CROSS := $(PKG_TOOLCHAIN_DIR)/bin/$(PKG_TOOLCHAIN_TARGET)-
  PKG_TOOLCHAIN_CC := $(PKG_TOOLCHAIN_CROSS)gcc
  PKG_TOOLCHAIN_LD := $(PKG_TOOLCHAIN_CROSS)ld
  PKG_TOOLCHAIN_AR := $(PKG_TOOLCHAIN_CROSS)ar
  PKG_TOOLCHAIN_OBJCOPY := $(PKG_TOOLCHAIN_CROSS)objcopy
  PKG_TOOLCHAIN_CFLAGS := -march=$(PKG_TOOLCHAIN_CPU_TYPE) -mabi=$(PKG_TOOLCHAIN_ABI)

endif
