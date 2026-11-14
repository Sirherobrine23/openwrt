# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk
include $(TOPDIR)/toolchain/auxiliary/profile.mk

PKG_NAME:=binutils
PKG_VERSION:=2.46.1
PKG_SOURCE:=binutils-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=@GNU/binutils/
PKG_HASH:=e127a709cba24c76de8936cb7083dd768f28cd37eb010492e2f19b71eb1294e4
HOST_BUILD_PARALLEL:=1

# Keep compiler patches scoped to this auxiliary source version.
PATCH_DIR:=$(CURDIR)/patches/$(PKG_VERSION)

include $(INCLUDE_DIR)/toolchain-build.mk

AUX_OUT_DIR:=$(HOST_BUILD_DIR)-build
HOST_STAMP_CONFIGURED:=$(AUX_OUT_DIR)/.configured
HOST_STAMP_BUILT:=$(AUX_OUT_DIR)/.built

# Do not install into the main target's $(TOOLCHAIN_DIR) or hostpkg.
define Host/Prepare
	$(call Host/Prepare/Default)
	rm -rf $(AUX_OUT_DIR)
	$(INSTALL_DIR) $(AUX_OUT_DIR)
endef

define Host/Configure
	(cd $(AUX_OUT_DIR) && \
		$(HOST_CONFIGURE_VARS) $(HOST_BUILD_DIR)/configure \
		--prefix=$(TOOLCHAIN_DIR) \
		--build=$(GNU_HOST_NAME) \
		--host=$(GNU_HOST_NAME) \
		--target=$(AUX_TARGET) \
		--disable-nls \
		--disable-werror \
		--disable-gdb \
		--disable-gprofng \
		--disable-sim \
		--disable-multilib \
		--without-zstd)
endef

define Host/Compile
	+$(MAKE) $(HOST_JOBS) -C $(AUX_OUT_DIR) all
endef

define Host/Install
	$(MAKE) -C $(AUX_OUT_DIR) install
	$(TOOLCHAIN_DIR)/bin/$(AUX_TARGET)-as --version >/dev/null
endef

define Host/Clean
	rm -rf $(HOST_BUILD_DIR) $(AUX_OUT_DIR)
endef

$(eval $(call HostBuild))
