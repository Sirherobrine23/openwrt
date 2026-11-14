# SPDX-License-Identifier: GPL-2.0-only
# Source metadata shared by the Linux and package toolchain assemblers.

PKG_SOURCE_URL:=@GNU/binutils/
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_CPE_ID:=cpe:/a:gnu:binutils

ifeq ($(PKG_VERSION),2.44)
  PKG_HASH:=ce2017e059d63e67ddb9240e9d4ec49c2893605035cd60e92ad53177f4377237
endif

ifeq ($(PKG_VERSION),2.45.1)
  PKG_HASH:=5fe101e6fe9d18fdec95962d81ed670fdee5f37e3f48f0bef87bddf862513aa5
endif

ifeq ($(PKG_VERSION),2.46.1)
  PKG_HASH:=e127a709cba24c76de8936cb7083dd768f28cd37eb010492e2f19b71eb1294e4
endif
