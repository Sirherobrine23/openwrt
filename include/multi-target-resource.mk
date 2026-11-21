# SPDX-License-Identifier: GPL-2.0-only
# Evaluate native directory names in the same environment as a worker.
TOPDIR ?= $(CURDIR)
include $(TOPDIR)/rules.mk

.PHONY: probe
probe:
	@set -eu; test -n '$(TARGET_DIR_NAME_NATIVE)' -a -n '$(TOOLCHAIN_DIR_NAME_NATIVE)'; \
	{ printf 'resource.target.$(OPENWRT_MULTI_CONTEXT) := %s\n' '$(TARGET_DIR_NAME_NATIVE)'; \
	  printf 'resource.host.$(OPENWRT_MULTI_CONTEXT) := host\n'; \
	  printf 'key.host.$(OPENWRT_MULTI_CONTEXT) := '; ./scripts/target-metadata.pl multi_config resource-key host $(OPENWRT_MULTI_CONTEXT) "$(OPENWRT_CONFIG)"; \
	  printf 'resource.toolchain.$(OPENWRT_MULTI_CONTEXT) := %s\n' '$(TOOLCHAIN_DIR_NAME_NATIVE)'; \
	  printf 'key.target.$(OPENWRT_MULTI_CONTEXT) := '; ./scripts/target-metadata.pl multi_config resource-key target $(OPENWRT_MULTI_CONTEXT) "$(OPENWRT_CONFIG)"; \
	  printf 'key.toolchain.$(OPENWRT_MULTI_CONTEXT) := '; ./scripts/target-metadata.pl multi_config resource-key toolchain $(OPENWRT_MULTI_CONTEXT) "$(OPENWRT_CONFIG)"; \
	} > "$(dir $(OPENWRT_CONFIG))/resources.mk"
