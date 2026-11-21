include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=leds
PKG_VERSION:=$(LINUX_VERSION)
PKG_RELEASE:=1

PKG_BUILD_PARALLEL:=1
PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/leds/default
  SECTION:=devel
  CATEGORY:=Development
  URL:=https://www.kernel.org
endef

define Package/ledumon
  $(Package/leds/default)
  TITLE:=Monitoring userspace LEDs
  DEPENDS:=+kmod-leds-uleds
endef

define Package/ledumon/description
  This program creates a new userspace LED class device and monitors it.
  A timestamp and brightness value is printed each time the brightness
  changes.
endef

define Package/ledhwbmon
  $(Package/leds/default)
  TITLE:=Monitoring hardware controlled LED brightness
endef

define Package/ledhwbmon/description
  This program monitors LED brightness level changes having its origin
  in hardware/firmware, i.e. outside of kernel control. A timestamp and
  brightness value is printed each time the brightness changes.
endef

MAKE_FLAGS = \
	ARCH="$(LINUX_KARCH)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	CC="$(TARGET_CC)" \
	LD="$(TARGET_CROSS)ld" \
	EXTRA_CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS) -static" \
	$(if $(findstring c,$(OPENWRT_VERBOSE)),V=1,V='') \
	prefix=/usr

LEDS_BUILD_DIR=$(if $(LINUX_EXTERNAL_BUILD),$(PKG_BUILD_DIR),$(LINUX_DIR)/tools/leds)

ifeq ($(LINUX_EXTERNAL_BUILD),1)
  define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(LINUX_SRC_DIR)/tools/leds/. $(PKG_BUILD_DIR)/
  endef
endif

define Build/Compile
	-$(MAKE) clean \
		-C $(LEDS_BUILD_DIR)
	+$(MAKE_FLAGS) $(MAKE) \
		$(if $(LINUX_EXTERNAL_BUILD),CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -I$(LINUX_SRC_DIR)/include/uapi") \
		-C $(LEDS_BUILD_DIR)
endef

define Package/ledumon/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(LEDS_BUILD_DIR)/uledmon \
		$(1)/usr/bin/ledumon
endef

define Package/ledhwbmon/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(LEDS_BUILD_DIR)/led_hw_brightness_mon \
		$(1)/usr/bin/ledhwbmon
endef

$(eval $(call BuildPackage,ledumon))
$(eval $(call BuildPackage,ledhwbmon))
