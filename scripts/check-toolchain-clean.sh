#!/bin/sh
# Multi-target allocation already hashes toolchain/build_version and recipes.
# A context-local marker must never delete another context's shared compiler.
[ -z "$OPENWRT_MULTI_CONTEXT" ] || exit 0

eval "$(grep CONFIG_GCC_VERSION "${OPENWRT_CONFIG:-.config}")"
CONFIG_TOOLCHAIN_BUILD_VER="$CONFIG_GCC_VERSION-$(cat toolchain/build_version)"
marker=.toolchain_build_ver
touch "$marker"
CURRENT_TOOLCHAIN_BUILD_VER="$(cat "$marker")"
[ -z "$CURRENT_TOOLCHAIN_BUILD_VER" ] && {
	echo "$CONFIG_TOOLCHAIN_BUILD_VER" > "$marker"
	exit 0
}
[ "$CONFIG_TOOLCHAIN_BUILD_VER" = "$CURRENT_TOOLCHAIN_BUILD_VER" ] && exit 0
echo "Toolchain build version changed ($CONFIG_TOOLCHAIN_BUILD_VER != $CURRENT_TOOLCHAIN_BUILD_VER), running make targetclean"
make targetclean
echo "$CONFIG_TOOLCHAIN_BUILD_VER" > "$marker"
exit 0
