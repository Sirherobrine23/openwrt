# SPDX-License-Identifier: GPL-2.0-only
# A worker changes only writable paths, never TOPDIR or the source tree.
ifndef __build_context_inc
__build_context_inc:=1
OPENWRT_CONFIG ?= $(TOPDIR)/.config
# Only metadata is contextual. Build and staging prefixes are native OpenWrt
# resources shared by all compatible subtargets.
OPENWRT_TMP_DIR := $(TOPDIR)/tmp$(if $(OPENWRT_MULTI_CONTEXT),/targets/$(OPENWRT_MULTI_CONTEXT)/work)
OPENWRT_HOST_NAME := host
OPENWRT_HOSTPKG_NAME := hostpkg
package_toolchain_dirname = toolchain-$(1)
# Do not export KCONFIG_CONFIG: the kernel and packages own their Kconfig.
export OPENWRT_CONFIG
endif
