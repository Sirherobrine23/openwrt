# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk
include $(TOPDIR)/toolchain/package-toolchain/profile.mk

PKG_NAME:=gcc
PKG_VERSION:=$(PTC_GCC_VERSION)
include $(TOPDIR)/toolchain/gcc/source.mk
PTC_COMPONENT:=GCC
include $(TOPDIR)/toolchain/package-toolchain/source.mk
HOST_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/toolchain-build.mk

PTC_OUT_DIR:=$(HOST_BUILD_DIR)-build
HOST_STAMP_PREPARED:=$(HOST_BUILD_DIR)/.prepared_$(PTC_CONFIG_HASH)
HOST_STAMP_CONFIGURED:=$(PTC_OUT_DIR)/.configured_$(PTC_CONFIG_HASH)
HOST_STAMP_BUILT:=$(PTC_OUT_DIR)/.built

define Host/Prepare
	$(call Host/Prepare/Default)
	rm -rf $(PTC_OUT_DIR)
	$(INSTALL_DIR) $(PTC_OUT_DIR)
endef

define Host/Configure
	(cd $(PTC_OUT_DIR) && \
		PATH="$(TOOLCHAIN_DIR)/bin:$$$$PATH" \
		$(HOST_CONFIGURE_VARS) $(PTC_GCC_CONFIGURE_VARS) $(HOST_BUILD_DIR)/configure \
		--prefix=$(TOOLCHAIN_DIR) \
		--build=$(GNU_HOST_NAME) \
		--host=$(GNU_HOST_NAME) \
		--target=$(PTC_TARGET) \
		--with-as=$(TOOLCHAIN_DIR)/bin/$(PTC_TARGET)-as \
		--with-ld=$(TOOLCHAIN_DIR)/bin/$(PTC_TARGET)-ld \
		--with-gmp=$(STAGING_DIR_HOST) \
		--with-mpfr=$(STAGING_DIR_HOST) \
		--with-mpc=$(STAGING_DIR_HOST) \
		--with-arch=$(PTC_CPU_TYPE) \
		--with-abi=$(PTC_ABI) \
		--enable-languages=$(PTC_LANGUAGES) \
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
		--disable-libstdcxx \
		$(PTC_GCC_CONFIGURE_ARGS))
endef

define Host/Compile
	+PATH="$(TOOLCHAIN_DIR)/bin:$$$$PATH" \
		$(MAKE) $(HOST_JOBS) $(PTC_GCC_MAKE_FLAGS) -C $(PTC_OUT_DIR) all-gcc all-target-libgcc
endef

define Host/Install
	PATH="$(TOOLCHAIN_DIR)/bin:$$$$PATH" \
		$(MAKE) $(PTC_GCC_MAKE_FLAGS) -C $(PTC_OUT_DIR) install-gcc install-target-libgcc
	$(TOOLCHAIN_DIR)/bin/$(PTC_TARGET)-gcc --version >/dev/null
endef

define Host/Clean
	rm -rf $(HOST_BUILD_DIR) $(PTC_OUT_DIR)
endef

$(eval $(call HostBuild))

# Direct component builds must honor the same profile configuration stamp.
$(HOST_STAMP_PREPARED): $(PTC_STAMP_PREPARED)
$(eval $(call PackageToolchain/Prepare))
