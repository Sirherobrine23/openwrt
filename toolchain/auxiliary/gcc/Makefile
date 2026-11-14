# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk
include $(TOPDIR)/toolchain/auxiliary/profile.mk

PKG_NAME:=gcc
PKG_VERSION:=$(AUX_GCC_VERSION)
PKG_SOURCE:=gcc-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=@GNU/gcc/gcc-$(PKG_VERSION)
HOST_BUILD_PARALLEL:=1

# Keep compiler patches scoped to this auxiliary source version.
PATCH_DIR:=$(CURDIR)/patches/$(PKG_VERSION)

ifeq ($(PKG_VERSION),13.4.0)
  PKG_HASH:=9c4ce6dbb040568fdc545588ac03c5cbc95a8dbf0c7aa490170843afb59ca8f5
else ifeq ($(PKG_VERSION),14.4.0)
  PKG_HASH:=752b6f567beac83159c77a7680b1316bdd784738bff9a9d070112c09da90f6d9
else ifeq ($(PKG_VERSION),15.3.0)
  PKG_HASH:=fa59c1beef8995f27c4d71c1df227587189315d3e6faff1bb4306e61b0c530eb
endif

include $(INCLUDE_DIR)/toolchain-build.mk

AUX_OUT_DIR:=$(HOST_BUILD_DIR)-build
HOST_STAMP_CONFIGURED:=$(AUX_OUT_DIR)/.configured
HOST_STAMP_BUILT:=$(AUX_OUT_DIR)/.built

define Host/Prepare
	$(call Host/Prepare/Default)
	rm -rf $(AUX_OUT_DIR)
	$(INSTALL_DIR) $(AUX_OUT_DIR)
endef

define Host/Configure
	(cd $(AUX_OUT_DIR) && \
		PATH="$(TOOLCHAIN_DIR)/bin:$$$$PATH" \
		$(HOST_CONFIGURE_VARS) $(HOST_BUILD_DIR)/configure \
		--prefix=$(TOOLCHAIN_DIR) \
		--build=$(GNU_HOST_NAME) \
		--host=$(GNU_HOST_NAME) \
		--target=$(AUX_TARGET) \
		--with-as=$(TOOLCHAIN_DIR)/bin/$(AUX_TARGET)-as \
		--with-ld=$(TOOLCHAIN_DIR)/bin/$(AUX_TARGET)-ld \
		--with-gmp=$(STAGING_DIR_HOST) \
		--with-mpfr=$(STAGING_DIR_HOST) \
		--with-mpc=$(STAGING_DIR_HOST) \
		--with-arch=$(AUX_CPU_TYPE) \
		--with-abi=$(AUX_ABI) \
		--enable-languages=c \
		--without-headers \
		--without-isl \
		--without-zstd \
		--disable-bootstrap \
		--disable-multilib \
		--disable-nls \
		--disable-shared \
		--disable-threads \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libssp \
		--disable-libstdcxx)
endef

define Host/Compile
	+PATH="$(TOOLCHAIN_DIR)/bin:$$$$PATH" \
		$(MAKE) $(HOST_JOBS) -C $(AUX_OUT_DIR) all-gcc all-target-libgcc
endef

define Host/Install
	PATH="$(TOOLCHAIN_DIR)/bin:$$$$PATH" \
		$(MAKE) -C $(AUX_OUT_DIR) install-gcc install-target-libgcc
	$(TOOLCHAIN_DIR)/bin/$(AUX_TARGET)-gcc --version >/dev/null
endef

define Host/Clean
	rm -rf $(HOST_BUILD_DIR) $(AUX_OUT_DIR)
endef

$(eval $(call HostBuild))
