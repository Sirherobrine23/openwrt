# SPDX-License-Identifier: GPL-2.0-only
# Build a package-selected bare-metal toolchain in native OpenWrt directories.
# GCC and Binutils use host-build.mk through toolchain-build.mk and share a
# profile-specific prefix, rather than staging_dir/hostpkg.

include $(TOPDIR)/rules.mk
include $(TOPDIR)/toolchain/auxiliary/profile.mk

.PHONY: all compile download clean
all: compile

# These must remain ordered even when the outer OpenWrt build uses -jN.
compile:
	+$(MAKE) -C binutils AUX_PROFILE="$(AUX_PROFILE)" host-compile
	+$(MAKE) -C gcc AUX_PROFILE="$(AUX_PROFILE)" host-compile

# Allow 'make download' and explicit auxiliary download before compilation.
download:
	+$(MAKE) -C binutils AUX_PROFILE="$(AUX_PROFILE)" download
	+$(MAKE) -C gcc AUX_PROFILE="$(AUX_PROFILE)" download

clean:
	+$(MAKE) -C gcc AUX_PROFILE="$(AUX_PROFILE)" host-clean
	+$(MAKE) -C binutils AUX_PROFILE="$(AUX_PROFILE)" host-clean
	rm -rf $(BUILD_DIR_TOOLCHAIN) $(TOOLCHAIN_DIR)
