# SPDX-License-Identifier: GPL-2.0-only
# Source metadata shared by the Linux and package toolchain compilers.

PKG_SOURCE_URL:=@GNU/gcc/gcc-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_CPE_ID:=cpe:/a:gnu:gcc

ifeq ($(PKG_VERSION),13.4.0)
  PKG_HASH:=9c4ce6dbb040568fdc545588ac03c5cbc95a8dbf0c7aa490170843afb59ca8f5
endif

ifeq ($(PKG_VERSION),14.4.0)
  PKG_HASH:=752b6f567beac83159c77a7680b1316bdd784738bff9a9d070112c09da90f6d9
endif

ifeq ($(PKG_VERSION),15.3.0)
  PKG_HASH:=fa59c1beef8995f27c4d71c1df227587189315d3e6faff1bb4306e61b0c530eb
endif
