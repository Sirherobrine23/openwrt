# SPDX-License-Identifier: GPL-2.0-only
# Included after rules.mk, only by toolchain/package-toolchain makefiles.

ifeq ($(strip $(PTC_PROFILE)),)
  $(error PTC_PROFILE is required)
endif
PTC_PROFILE_FOUND :=
include $(TMP_DIR)/.package-toolchains.mk
ifneq ($(PTC_PROFILE_FOUND),1)
  $(error Unknown package toolchain profile '$(PTC_PROFILE)'; run make defconfig)
endif

override BUILD_DIR_TOOLCHAIN := $(BUILD_DIR_BASE)/toolchain-$(PTC_PROFILE)
override TOOLCHAIN_DIR := $(TOPDIR)/staging_dir/toolchain-$(PTC_PROFILE)

# Remove previous markers when configuration changes, including A -> B -> A.
# The prefix is private to this profile, so removing it also drops stale tools
# left by a previous language selection or compiler fork.
PTC_STAMP_PREPARED := $(BUILD_DIR_TOOLCHAIN)/.prepared_$(PTC_CONFIG_HASH)

define PackageToolchain/Prepare
$(PTC_STAMP_PREPARED):
	rm -rf $(BUILD_DIR_TOOLCHAIN) $(TOOLCHAIN_DIR)
	mkdir -p $(BUILD_DIR_TOOLCHAIN)
	touch $$@
endef
