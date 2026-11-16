# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=opennpu
PKG_VERSION:=8.0.0
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://sirherobrine23.com.br/airoha/OpenNPU.git
PKG_SOURCE_DATE:=2026-11-15
PKG_SOURCE_VERSION:=7d2e33b7795106561066906ac3e299ab6791ff1b
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.xz

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Matheus Sampaio Queiroga <srherobrine20@gmail.com>
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-iremap no-lto no-mold
PKG_CONFIG_DEPENDS:=CONFIG_OPENNPU_RX_PROFILE

# Consumed by this branch's include/package-toolchain.mk via package.mk.
# This compiler builds firmware; TARGET_* continues to describe Linux.
# Both compiler forks use their en7523 branch, pinned below. The variant
# isolates these sources from stock GNU profiles used by other packages.
PKG_TOOLCHAIN:=opennpu-rv32

define Toolchain/opennpu-rv32
  PKG_TOOLCHAIN_ARCH:=riscv64
  PKG_TOOLCHAIN_TARGET:=riscv64-unknown-elf
  PKG_TOOLCHAIN_CPU_TYPE:=rv32im_zicsr_zifencei
  PKG_TOOLCHAIN_ABI:=ilp32
  PKG_TOOLCHAIN_LIBC:=none
  PKG_TOOLCHAIN_LANGUAGES:=c
  PKG_TOOLCHAIN_VARIANT:=en7523
  PKG_TOOLCHAIN_GCC_VERSION:=14.4.0
  PKG_TOOLCHAIN_GCC_SOURCE_PROTO:=git
  PKG_TOOLCHAIN_GCC_SOURCE_URL:=https://sirherobrine23.com.br/airoha/gcc.git
  PKG_TOOLCHAIN_GCC_SOURCE_VERSION:=da3eb5078c2ab9d081dd00032de9c363b046ca50
  PKG_TOOLCHAIN_GCC_SOURCE_DATE:=2026-11-13

  PKG_TOOLCHAIN_BINUTILS_VERSION:=2.46.1
  PKG_TOOLCHAIN_BINUTILS_SOURCE_PROTO:=git
  PKG_TOOLCHAIN_BINUTILS_SOURCE_URL:=https://sirherobrine23.com.br/airoha/binutils.git
  PKG_TOOLCHAIN_BINUTILS_SOURCE_VERSION:=5fe3f4fe261bd6dc91fc4b04d07e9622ba27dfa8
  PKG_TOOLCHAIN_BINUTILS_SOURCE_DATE:=2026-11-13
endef

include $(INCLUDE_DIR)/package.mk

# These packages contain only firmware data, without target userspace binaries.
PKG_DEFAULT_DEPENDS:=

opennpu_lower = $(shell printf '%s' '$(1)' | tr '[:upper:]' '[:lower:]')
opennpu_prefix = $(patsubst %_nowifi,%,$(call opennpu_lower,$(1)))
opennpu_provider = airoha-$(subst _,-,$(call opennpu_prefix,$(1)))-npu-firmware
opennpu_package = $(call opennpu_provider,$(1))

OPENNPU_PRESET = $(call opennpu_lower,$(BUILD_VARIANT))_defconfig
OPENNPU_MAKE_FLAGS = \
	CROSS_COMPILE="$(PKG_TOOLCHAIN_CROSS)" \
	HOSTCC="$(HOSTCC)" \
	HOSTCFLAGS="$(HOST_CFLAGS)" \
	HOSTLDFLAGS="$(HOST_LDFLAGS)" \
	PYTHON="$(STAGING_DIR_HOST)/bin/python3" \
	KCONFIG_CONFIG="$(PKG_BUILD_DIR)/.config" \
	O="$(PKG_BUILD_DIR)/build" \
	OUTPUT="$(PKG_BUILD_DIR)/firmware" \
	GITREV="$(PKG_SOURCE_VERSION)"

define Package/opennpu/Default
  SECTION:=firmware
  CATEGORY:=Firmware
  SUBMENU:=Airoha NPU Firmware
  URL:=https://sirherobrine23.com.br/airoha/OpenNPU
  DEPENDS:=@TARGET_airoha
  PKGARCH:=all
endef

# Normal package builds use conf/olddefconfig, without opening ncurses.
# The per-variant build directory keeps each firmware configuration isolated.
define Build/Configure
	test -f "$(PKG_BUILD_DIR)/configs/$(OPENNPU_PRESET)"
	$(CP) "$(PKG_BUILD_DIR)/configs/$(OPENNPU_PRESET)" "$(PKG_BUILD_DIR)/.config"
	$(if $(and $(filter EN7523_KITE,$(BUILD_VARIANT)),$(filter y,$(CONFIG_OPENNPU_RX_PROFILE))),printf '%s\n' 'CONFIG_RX_PROFILE=y' >> "$(PKG_BUILD_DIR)/.config")
	+$(MAKE) -C "$(PKG_BUILD_DIR)" $(OPENNPU_MAKE_FLAGS) olddefconfig
endef

define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C "$(PKG_BUILD_DIR)" $(OPENNPU_MAKE_FLAGS) all
endef

# Each Package has an independent OpenWrt VARIANT and provides the firmware
# name already used by the board/driver dependencies. Conflicts follow the
# alternative-firmware pattern used by ath10k-ct-firmware in OpenWrt.
define Firmware/Variant
  define Package/$(call opennpu_package,$(1)_$(2))
    $$(call Package/opennpu/Default)
    TITLE:=OpenNPU firmware for $(1) ($(2))
    VARIANT:=$(1)_$(2)
    PROVIDES:=$(call opennpu_provider,$(1)_$(2))
  endef

  define Package/$(call opennpu_package,$(1)_$(2))/description
OpenNPU bare-metal RV32 firmware for $(1) with $(2).
The EN7523/KITE variant shares one native RX backend between MT7915,
MT7915 DBDC and MT7916, configured by the Linux mailbox.
Other variants retain the imported Clanker platform implementations.
  endef

  define Package/$(call opennpu_package,$(1)_$(2))/install
	$$(INSTALL_DIR) $$(1)/lib/firmware/airoha
	$$(INSTALL_DATA) \
		$$(PKG_BUILD_DIR)/firmware/$(call opennpu_prefix,$(1)_$(2))_npu_rv32.bin \
		$$(PKG_BUILD_DIR)/firmware/$(call opennpu_prefix,$(1)_$(2))_npu_data.bin \
		$$(1)/lib/firmware/airoha/
  endef

  $$(eval $$(call BuildPackage,$(call opennpu_package,$(1)_$(2))))
endef

define Package/airoha-en7523-kite-npu-firmware/config
  config OPENNPU_RX_PROFILE
    bool "Sample EN7523 RX stage timings"
    default n
    help
      Enable sampled native RX timing counters. Adds overhead; leave disabled
      for normal operation and throughput comparisons.
endef

# Same presets as OpenNPU/configs/.
$(foreach wifi,NOWIFI KITE,$(eval $(call Firmware/Variant,EN7523,$(wifi))))
$(foreach wifi,NOWIFI MT7916 MT7991 MT7993,$(eval $(call Firmware/Variant,AN7552,$(wifi))))
$(foreach wifi,NOWIFI MT7916 MT7992 MT7996,$(eval $(call Firmware/Variant,AN7581,$(wifi))))
$(foreach wifi,NOWIFI MT7916 MT7992 MT7993 MT7996,$(eval $(call Firmware/Variant,AN7583,$(wifi))))
