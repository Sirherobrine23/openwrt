# SPDX-License-Identifier: GPL-2.0-only
# Package-selected secondary compiler; TARGET_* always refers to Linux.

# Definitions and selection must precede package.mk. A single definition can
# be selected implicitly; multiple definitions require PKG_TOOLCHAIN.
_ptc_definitions := $(patsubst Toolchain/%,%,$(filter Toolchain/%,$(.VARIABLES)))
ifeq ($(strip $(PKG_TOOLCHAIN)),)
  ifeq ($(words $(_ptc_definitions)),1)
    PKG_TOOLCHAIN := $(_ptc_definitions)
  else ifneq ($(_ptc_definitions),)
    $(error Select one Toolchain definition with PKG_TOOLCHAIN)
  endif
endif
ifneq ($(strip $(PKG_TOOLCHAIN)),)
  ifeq ($(filter $(PKG_TOOLCHAIN),$(_ptc_definitions)),)
    $(error Unknown Toolchain/$(PKG_TOOLCHAIN))
  endif
  $(eval $(Toolchain/$(PKG_TOOLCHAIN)))
endif

# Unprefixed source/configuration settings are shorthand for GCC settings.
_ptc_source_fields := SOURCE SOURCE_PROTO SOURCE_URL SOURCE_VERSION SOURCE_DATE SOURCE_SUBDIR HASH MIRROR_HASH
_ptc_component_fields := $(_ptc_source_fields) PATCH_DIR CONFIGURE_ARGS CONFIGURE_VARS MAKE_FLAGS
PKG_TOOLCHAIN_FIELDS := ARCH TARGET CPU_TYPE ABI LIBC GCC_VERSION BINUTILS_VERSION LANGUAGES VARIANT CONFIG_HASH \
  $(addprefix GCC_,$(_ptc_component_fields)) $(addprefix BINUTILS_,$(_ptc_component_fields))

ifneq ($(strip $(PKG_TOOLCHAIN)),)
  ifeq ($(strip $(PKG_TOOLCHAIN_ARCH)$(PKG_TOOLCHAIN_TARGET)),)
    $(error Toolchain/$(PKG_TOOLCHAIN) must declare an architecture or target)
  endif
endif

ifneq ($(strip $(PKG_TOOLCHAIN_ARCH)$(PKG_TOOLCHAIN_TARGET)),)
  $(foreach v,$(_ptc_component_fields),$(if $(filter undefined,$(origin PKG_TOOLCHAIN_GCC_$(v))),$(eval PKG_TOOLCHAIN_GCC_$(v) := $(PKG_TOOLCHAIN_$(v)))))
  ifeq ($(strip $(PKG_TOOLCHAIN_TARGET)),)
    PKG_TOOLCHAIN_TARGET := $(if $(filter riscv64,$(PKG_TOOLCHAIN_ARCH)),riscv64-unknown-elf)
  endif
  ifeq ($(strip $(PKG_TOOLCHAIN_ARCH)),)
    PKG_TOOLCHAIN_ARCH := $(firstword $(subst -, ,$(PKG_TOOLCHAIN_TARGET)))
  endif
  PKG_TOOLCHAIN_CPU_TYPE ?= rv32imac
  PKG_TOOLCHAIN_ABI ?= ilp32
  PKG_TOOLCHAIN_LIBC ?= none
  # DUMP intentionally skips .config in rules.mk. Read only these two values,
  # so source metadata and the package build select the same compiler release.
  _ptc_config_version = $(or $(call qstrip,$(CONFIG_$(1)_VERSION)),$(shell sed -n 's/^CONFIG_$(1)_VERSION="\([^"]*\)"$$/\1/p' $(OPENWRT_CONFIG) 2>/dev/null),$(2))
  PKG_TOOLCHAIN_GCC_VERSION ?= $(call _ptc_config_version,GCC,14.4.0)
  PKG_TOOLCHAIN_BINUTILS_VERSION ?= $(call _ptc_config_version,BINUTILS,2.46.1)
  PKG_TOOLCHAIN_GCC_VERSION := $(PKG_TOOLCHAIN_GCC_VERSION)
  PKG_TOOLCHAIN_BINUTILS_VERSION := $(PKG_TOOLCHAIN_BINUTILS_VERSION)
  PKG_TOOLCHAIN_LANGUAGES ?= c

  ifneq ($(PKG_TOOLCHAIN_ARCH):$(PKG_TOOLCHAIN_TARGET),riscv64:riscv64-unknown-elf)
    $(error Unsupported package toolchain $(PKG_TOOLCHAIN_ARCH):$(PKG_TOOLCHAIN_TARGET))
  endif
  ifeq ($(filter rv32% rv64%,$(PKG_TOOLCHAIN_CPU_TYPE)),)
    $(error Unsupported PKG_TOOLCHAIN_CPU_TYPE '$(PKG_TOOLCHAIN_CPU_TYPE)')
  endif
  ifeq ($(filter ilp32 ilp32f ilp32d lp64 lp64f lp64d,$(PKG_TOOLCHAIN_ABI)),)
    $(error Unsupported PKG_TOOLCHAIN_ABI '$(PKG_TOOLCHAIN_ABI)')
  endif
  ifneq ($(filter rv32%,$(PKG_TOOLCHAIN_CPU_TYPE)),)
    ifeq ($(filter ilp32%,$(PKG_TOOLCHAIN_ABI)),)
      $(error RV32 requires an ilp32 ABI)
    endif
  else
    ifeq ($(filter lp64%,$(PKG_TOOLCHAIN_ABI)),)
      $(error RV64 requires an lp64 ABI)
    endif
  endif
  ifneq ($(PKG_TOOLCHAIN_LIBC),none)
    $(error Unsupported PKG_TOOLCHAIN_LIBC '$(PKG_TOOLCHAIN_LIBC)' (bare-metal only))
  endif
  $(foreach c,GCC BINUTILS,\
    $(if $(strip $(PKG_TOOLCHAIN_$(c)_VERSION)),,\
      $(error PKG_TOOLCHAIN_$(c)_VERSION is required))\
    $(if $(PKG_TOOLCHAIN_$(c)_SOURCE_PROTO),\
      $(if $(PKG_TOOLCHAIN_$(c)_SOURCE_URL),,\
        $(error PKG_TOOLCHAIN_$(c)_SOURCE_URL is required))\
      $(if $(PKG_TOOLCHAIN_$(c)_SOURCE_VERSION),,\
        $(error PKG_TOOLCHAIN_$(c)_SOURCE_VERSION is required (commit, tag or branch)))))

  $(foreach v,CPU_TYPE GCC_VERSION BINUTILS_VERSION $(if $(PKG_TOOLCHAIN_VARIANT),VARIANT),\
    $(if $(shell printf '%s' '$(PKG_TOOLCHAIN_$(v))' | grep -E '^[a-zA-Z0-9_.+-]+$$'),,\
      $(error Invalid PKG_TOOLCHAIN_$(v) '$(PKG_TOOLCHAIN_$(v))')))

  # Relative patch paths belong to the package, not toolchain/package-toolchain/*.
  $(foreach c,GCC BINUTILS,$(if $(PKG_TOOLCHAIN_$(c)_PATCH_DIR),$(eval PKG_TOOLCHAIN_$(c)_PATCH_DIR := $(abspath $(PKG_TOOLCHAIN_$(c)_PATCH_DIR)))))
  _ptc_recipe_files := $(TOPDIR)/include/package-toolchain.mk \
    $(TOPDIR)/toolchain/gcc/source.mk $(TOPDIR)/toolchain/binutils/source.mk \
    $(wildcard $(TOPDIR)/toolchain/package-toolchain/*.mk $(TOPDIR)/toolchain/package-toolchain/*/Makefile)
  _ptc_recipe_hash := $(shell $(MKHASH) sha256 $(_ptc_recipe_files) | $(MKHASH) md5)
  PKG_FILE_DEPENDS += $(_ptc_recipe_files)
  PKG_TOOLCHAIN_PATCH_FILES := $(sort $(foreach c,GCC BINUTILS,$(if $(PKG_TOOLCHAIN_$(c)_PATCH_DIR),$(shell find '$(PKG_TOOLCHAIN_$(c)_PATCH_DIR)' -type f 2>/dev/null))))
  PKG_FILE_DEPENDS += $(PKG_TOOLCHAIN_PATCH_FILES)
  $(foreach c,GCC BINUTILS,$(if $(PKG_TOOLCHAIN_$(c)_PATCH_DIR),$(if $(wildcard $(PKG_TOOLCHAIN_$(c)_PATCH_DIR)/.),,$(error Missing package toolchain patch directory $(PKG_TOOLCHAIN_$(c)_PATCH_DIR)))))
  _ptc_patch_hash := $(if $(PKG_TOOLCHAIN_PATCH_FILES),$(shell $(MKHASH) sha256 $(PKG_TOOLCHAIN_PATCH_FILES) | $(MKHASH) md5))
  _ptc_config := $(foreach v,$(filter-out CONFIG_HASH,$(PKG_TOOLCHAIN_FIELDS)),$(v)=$(strip $(PKG_TOOLCHAIN_$(v)));) PATCH_HASH=$(_ptc_patch_hash) RECIPE_HASH=$(_ptc_recipe_hash)
  _ptc_hash := $(shell printf '%s' '$(subst ','\'',$(_ptc_config))' | $(MKHASH) md5)
  ifeq ($(_ptc_hash),)
    $(error Could not hash package toolchain configuration)
  endif
  # Like packages: readable identity in paths, configuration hash in stamps.
  PKG_TOOLCHAIN_CONFIG_HASH := $(_ptc_hash)
  PKG_TOOLCHAIN_PROFILE := $(PKG_TOOLCHAIN_TARGET)__$(PKG_TOOLCHAIN_CPU_TYPE)__$(PKG_TOOLCHAIN_ABI)__gcc-$(PKG_TOOLCHAIN_GCC_VERSION)$(if $(PKG_TOOLCHAIN_VARIANT),__$(PKG_TOOLCHAIN_VARIANT))
  ifneq ($(words $(PKG_TOOLCHAIN_PROFILE)),1)
    $(error Invalid package toolchain profile '$(PKG_TOOLCHAIN_PROFILE)')
  endif
  PKG_TOOLCHAIN_DIR := $(TOPDIR)/staging_dir/$(call package_toolchain_dirname,$(PKG_TOOLCHAIN_PROFILE),$(PKG_TOOLCHAIN_CONFIG_HASH))
  PKG_TOOLCHAIN_CROSS := $(PKG_TOOLCHAIN_DIR)/bin/$(PKG_TOOLCHAIN_TARGET)-
  PKG_TOOLCHAIN_CC := $(PKG_TOOLCHAIN_CROSS)gcc
  PKG_TOOLCHAIN_CXX := $(PKG_TOOLCHAIN_CROSS)g++
  PKG_TOOLCHAIN_LD := $(PKG_TOOLCHAIN_CROSS)ld
  PKG_TOOLCHAIN_AR := $(PKG_TOOLCHAIN_CROSS)ar
  PKG_TOOLCHAIN_OBJCOPY := $(PKG_TOOLCHAIN_CROSS)objcopy
  PKG_TOOLCHAIN_CFLAGS := -march=$(PKG_TOOLCHAIN_CPU_TYPE) -mabi=$(PKG_TOOLCHAIN_ABI)
endif
