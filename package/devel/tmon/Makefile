include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=tmon
PKG_VERSION:=$(LINUX_VERSION)
PKG_RELEASE:=1

PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/tmon
  SECTION:=devel
  CATEGORY:=Development
  TITLE:=Thermal monitoring and testing tool
  URL:=https://www.kernel.org
  DEPENDS:=+libncursesw
endef

define Package/tmon/description
  As hardware vendors cope with the thermal constraints on their products,
  more and more sensors are added, new cooling capabilities are introduced.
  To expose such relationship to the userspace, Linux generic thermal layer
  introduced sysfs entry at /sys/class/thermal with a matrix of symbolic
  links, trip point bindings, and device instances. To traverse such
  matrix by hand is not a trivial task.
  'TMON' is conceived as a tool to help visualize, tune, and test the
  complex thermal subsystem.
endef

MAKE_FLAGS = \
	ARCH="$(LINUX_KARCH)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	CC="$(TARGET_CC)" \
	CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS)"

TMON_BUILD_DIR=$(if $(LINUX_EXTERNAL_BUILD),$(PKG_BUILD_DIR)/tools/thermal/tmon,$(LINUX_DIR)/tools/thermal/tmon)

ifeq ($(LINUX_EXTERNAL_BUILD),1)
  define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)/tools/thermal $(PKG_BUILD_DIR)/tools/build
	$(CP) $(LINUX_SRC_DIR)/tools/thermal/tmon $(PKG_BUILD_DIR)/tools/thermal/
	$(CP) $(LINUX_SRC_DIR)/tools/build/Build.include $(PKG_BUILD_DIR)/tools/build/
  endef
endif

define Build/Compile
	-$(MAKE) clean \
		-C $(TMON_BUILD_DIR)
	+$(MAKE_FLAGS) $(MAKE) \
		-C $(TMON_BUILD_DIR)
endef

define Package/tmon/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(TMON_BUILD_DIR)/tmon \
		$(1)/usr/bin/
endef

$(eval $(call BuildPackage,tmon))
