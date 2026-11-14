# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk
include $(TOPDIR)/toolchain/package-toolchain/profile.mk

PKG_NAME:=binutils
PKG_VERSION:=$(PTC_BINUTILS_VERSION)
include $(TOPDIR)/toolchain/binutils/source.mk
PTC_COMPONENT:=BINUTILS
include $(TOPDIR)/toolchain/package-toolchain/source.mk
HOST_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/toolchain-build.mk

PTC_OUT_DIR:=$(HOST_BUILD_DIR)-build
HOST_STAMP_PREPARED:=$(HOST_BUILD_DIR)/.prepared_$(PTC_CONFIG_HASH)
HOST_STAMP_CONFIGURED:=$(PTC_OUT_DIR)/.configured_$(PTC_CONFIG_HASH)
HOST_STAMP_BUILT:=$(PTC_OUT_DIR)/.built

# Do not install into the main target's $(TOOLCHAIN_DIR) or hostpkg.
define Host/Prepare
	$(call Host/Prepare/Default)
	rm -rf $(PTC_OUT_DIR)
	$(INSTALL_DIR) $(PTC_OUT_DIR)
endef

define Host/Configure
	(cd $(PTC_OUT_DIR) && \
		$(HOST_CONFIGURE_VARS) $(PTC_BINUTILS_CONFIGURE_VARS) $(HOST_BUILD_DIR)/configure \
		--prefix=$(TOOLCHAIN_DIR) \
		--build=$(GNU_HOST_NAME) \
		--host=$(GNU_HOST_NAME) \
		--target=$(PTC_TARGET) \
		--disable-nls \
		--disable-werror \
		--disable-gdb \
		--disable-gprofng \
		--disable-sim \
		--disable-multilib \
		--without-zstd \
		$(PTC_BINUTILS_CONFIGURE_ARGS))
endef

define Host/Compile
	+$(MAKE) $(HOST_JOBS) $(PTC_BINUTILS_MAKE_FLAGS) -C $(PTC_OUT_DIR) all
endef

define Host/Install
	$(MAKE) $(PTC_BINUTILS_MAKE_FLAGS) -C $(PTC_OUT_DIR) install
	$(TOOLCHAIN_DIR)/bin/$(PTC_TARGET)-as --version >/dev/null
endef

define Host/Clean
	rm -rf $(HOST_BUILD_DIR) $(PTC_OUT_DIR)
endef

$(eval $(call HostBuild))

# Direct component builds must honor the same profile configuration stamp.
$(HOST_STAMP_PREPARED): $(PTC_STAMP_PREPARED)
$(eval $(call PackageToolchain/Prepare))
