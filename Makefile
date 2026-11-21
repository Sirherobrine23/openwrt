# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007 OpenWrt.org

TOPDIR:=${CURDIR}
LC_ALL:=C
LANG:=C
TZ:=UTC
export TOPDIR LC_ALL LANG TZ

empty:=
space:= $(empty) $(empty)
$(if $(findstring $(space),$(TOPDIR)),$(error ERROR: The path to the OpenWrt directory must not include any spaces))

world:

include $(TOPDIR)/include/build-context.mk

ifeq ($(strip $(OPENWRT_MULTI_CONTEXT)$(filter 1,$(OPENWRT_BUILD) $(OPENWRT_MULTI_INTERNAL) $(SDK) $(IB))),)
  include $(TOPDIR)/include/multi-target.mk
else

DISTRO_PKG_CONFIG:=$(shell $(TOPDIR)/scripts/command_all.sh pkg-config | grep -e '/usr' -e '/nix/store' -m 1)

export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
export PATH:=$(TOPDIR)/staging_dir/$(OPENWRT_HOST_NAME)/bin:$(PATH)

ifneq ($(OPENWRT_BUILD),1)
  _SINGLE=export MAKEFLAGS=$(space);

  override OPENWRT_BUILD=1
  export OPENWRT_BUILD
  GREP_OPTIONS=
  export GREP_OPTIONS
  CDPATH=
  export CDPATH
  include $(TOPDIR)/include/debug.mk
  include $(TOPDIR)/include/depends.mk
  include $(TOPDIR)/include/toplevel.mk
else
  include rules.mk
  include $(INCLUDE_DIR)/depends.mk
  include $(INCLUDE_DIR)/subdir.mk
  include target/Makefile
  include package/Makefile
  include tools/Makefile
  include toolchain/Makefile

# Include the test suite Makefile if it exists
-include tests/Makefile

$(toolchain/stamp-compile): $(tools/stamp-compile) $(if $(CONFIG_BUILDBOT),toolchain_rebuild_check)
$(target/stamp-compile): $(toolchain/stamp-compile) $(tools/stamp-compile) $(BUILD_DIR)/.prepared
$(package/stamp-compile): $(target/stamp-compile) $(package/stamp-cleanup)
$(package/stamp-install): $(package/stamp-compile)
$(target/stamp-install): $(package/stamp-compile) $(package/stamp-install)
check: $(tools/stamp-check) $(toolchain/stamp-check) $(package/stamp-check)

printdb:
	@true

prepare: $(target/stamp-compile)

_clean: FORCE
	rm -rf $(BUILD_DIR) $(STAGING_DIR) $(BIN_DIR) $(PACKAGE_REPO_DIR) $(if $(OPENWRT_MULTI_CONTEXT),$(PACKAGE_DIR_ALL) $(PACKAGE_DIR_ALL).list,$(TOPDIR)/staging_dir/packages)

clean: _clean
	rm -rf $(BUILD_LOG_DIR)

targetclean: _clean
ifneq ($(OPENWRT_MULTI_CONTEXT),)
	+@set -e; for profile in $$(sed -n 's/^ifeq (\$$(PTC_PROFILE),\([a-zA-Z0-9_.+-]*\))$$/\1/p' $(TMP_DIR)/.package-toolchains.mk); do \
		$(SUBMAKE) "toolchain/package-toolchain/$$profile/clean"; \
	done
endif
	rm -rf $(TOOLCHAIN_DIR) $(BUILD_DIR_BASE)/$(OPENWRT_HOSTPKG_NAME) $(BUILD_DIR_TOOLCHAIN)

dirclean: targetclean clean
	rm -rf $(STAGING_DIR_HOST) $(STAGING_DIR_HOSTPKG) $(BUILD_DIR_BASE)/$(OPENWRT_HOST_NAME)
	rm -rf $(TMP_DIR)
	$(if $(OPENWRT_MULTI_CONTEXT),:,$(MAKE) -C $(TOPDIR)/scripts/config clean)

toolchain_rebuild_check:
	$(SCRIPT_DIR)/check-toolchain-clean.sh

cacheclean:
ifneq ($(CONFIG_CCACHE),)
	$(STAGING_DIR_HOST)/bin/ccache -C
endif

ifndef DUMP_TARGET_DB
$(BUILD_DIR)/.prepared: Makefile
	@mkdir -p $$(dirname $@)
	@touch $@

$(TMP_DIR)/.prereq_packages: $(OPENWRT_CONFIG)
	unset ERROR; \
	for package in $(sort $(prereq-y) $(prereq-m)); do \
		$(_SINGLE)$(NO_TRACE_MAKE) -s -r -C package/$$package prereq || ERROR=1; \
	done; \
	if [ -n "$$ERROR" ]; then \
		echo "Package prerequisite check failed."; \
		false; \
	fi
	touch $@
endif

# check prerequisites before starting to build
prereq: $(target/stamp-prereq) $(TMP_DIR)/.prereq_packages
	@if [ ! -f "$(INCLUDE_DIR)/site/$(ARCH)" ]; then \
		echo 'ERROR: Missing site config for architecture "$(ARCH)" !'; \
		echo '       The missing file will cause configure scripts to fail during compilation.'; \
		echo '       Please provide a "$(INCLUDE_DIR)/site/$(ARCH)" file and restart the build.'; \
		exit 1; \
	fi

$(BIN_DIR)/profiles.json: FORCE
	$(if $(CONFIG_JSON_OVERVIEW_IMAGE_INFO), \
		mkdir -p $(BIN_DIR) $(TMP_DIR); \
		WORK_DIR=$(BUILD_DIR)/json_info_files \
			$(SCRIPT_DIR)/json_overview_image_info.py $(TMP_DIR)/.profiles.json && \
		$(call cp_if_changed,$(TMP_DIR)/.profiles.json,$@) \
	)

json_overview_image_info: $(BIN_DIR)/profiles.json

checksum: FORCE
	$(call sha256sums,$(BIN_DIR),$(CONFIG_BUILDBOT))

buildversion: FORCE
	mkdir -p $(BIN_DIR) $(TMP_DIR)
	$(SCRIPT_DIR)/getver.sh > $(TMP_DIR)/.version.buildinfo
	$(call cp_if_changed,$(TMP_DIR)/.version.buildinfo,$(BIN_DIR)/version.buildinfo)

feedsversion: FORCE
	mkdir -p $(BIN_DIR) $(TMP_DIR)
	$(SCRIPT_DIR)/feeds list -fs > $(TMP_DIR)/.feeds.buildinfo
	$(call cp_if_changed,$(TMP_DIR)/.feeds.buildinfo,$(BIN_DIR)/feeds.buildinfo)

# diffconfig.sh runs the config parser over the whole tree twice, which takes
# two seconds of every build. Skip it while neither .config nor a Kconfig file
# is newer than the file it wrote last time. include/toplevel.mk guards the
# sync check of .config the same way.
DIFFCONFIG_FILES:=$(OPENWRT_CONFIG) Config.in config target toolchain package feeds \
	tmp/.config-package.in tmp/.config-target.in tmp/.config-feeds.in scripts/config/conf

diffconfig: FORCE
	mkdir -p $(BIN_DIR)
	@[ -f $(BIN_DIR)/config.buildinfo ] && \
		[ -z "$$(find $(DIFFCONFIG_FILES) -newer $(BIN_DIR)/config.buildinfo \
			\( -name .config -o -name conf -o -name '*.in' -o -name 'Config.*' \) \
			-print -quit 2>/dev/null)" ] || \
		$(SCRIPT_DIR)/diffconfig.sh > $(BIN_DIR)/config.buildinfo

buildinfo: FORCE
	$(_SINGLE)$(SUBMAKE) -r diffconfig buildversion feedsversion

prepare: $(OPENWRT_CONFIG) $(tools/stamp-compile) $(toolchain/stamp-compile)
	$(_SINGLE)$(SUBMAKE) -r buildinfo

world: prepare $(target/stamp-compile) $(package/stamp-compile) $(package/stamp-install) $(target/stamp-install) FORCE
	$(_SINGLE)$(SUBMAKE) -r package/index json_overview_image_info checksum
ifneq ($(CONFIG_CCACHE),)
	$(STAGING_DIR_HOST)/bin/ccache -s
endif

.PHONY: clean dirclean prereq prepare world package/symlinks package/symlinks-install package/symlinks-clean

endif

endif # native build context
