# SPDX-License-Identifier: GPL-2.0-only
# GNU Make owns frontend invocation, config resolution and context generation.
TOPDIR ?= $(CURDIR)
STATE := tmp/multi-target
CONFIG_TOOL := ./scripts/target-metadata.pl multi_config
CONF := scripts/config/conf
KCONF_FLAGS := $(if $(filter 1,$(RECURSIVE_DEP_IS_ERROR)),--fatalrecursive)
# Explicitly isolate the executable Kconfig's generated auxiliary files.
# Never export KCONFIG_CONFIG to the recursive package/kernel builds.
kconfig = KCONFIG_CONFIG="$(1)" KCONFIG_AUTOCONFIG="$(dir $(1))kconfig/auto.conf" KCONFIG_AUTOHEADER="$(dir $(1))kconfig/autoconf.h" KCONFIG_RUSTCCFG="$(dir $(1))kconfig/rustc_cfg"
replace = if [ ! -f "$(2)" ] || ! cmp -s "$(1)" "$(2)"; then cp "$(1)" "$(2).new" && mv "$(2).new" "$(2)"; fi
.PHONY: configure prepare split
# Frontends read and write the public .config, including their Save dialog.
# Only generated Kconfig auxiliary files live under the metadata directory.
frontend_kconfig = KCONFIG_CONFIG=".config" KCONFIG_AUTOCONFIG="$(STATE)/kconfig/auto.conf" KCONFIG_AUTOHEADER="$(STATE)/kconfig/autoconf.h" KCONFIG_RUSTCCFG="$(STATE)/kconfig/rustc_cfg"
configure:
	@set -eu; mkdir -p $(STATE); \
	board=$$($(CONFIG_TOOL) board .config); \
	for attempt in 1 2 3 4; do \
		$(CONFIG_TOOL) generate "$$board"; \
		$(CONFIG_TOOL) seed .config "$$board" $(STATE)/global.seed; \
		if ! cmp -s $(STATE)/global.seed .config; then \
			if [ -f .config ]; then cp -L .config .config.old; fi; \
			if [ -L .config ]; then cat $(STATE)/global.seed > .config; else cp $(STATE)/global.seed .config.new && mv .config.new .config; fi; \
		fi; \
		$(frontend_kconfig) $(FRONTEND) $(FRONTEND_FLAGS) $(STATE)/Config.in; \
		new_board=$$($(CONFIG_TOOL) board .config); \
		if [ "$$new_board" = "$$board" ]; then \
			$(frontend_kconfig) $(CONF) --savedefconfig=$(STATE)/global.minimal $(STATE)/Config.in; \
			$(CONFIG_TOOL) save .config $(STATE)/global.minimal $(STATE)/global.saved; \
			if ! cmp -s $(STATE)/global.saved .config; then \
				if [ -L .config ]; then cat $(STATE)/global.saved > .config; else cp $(STATE)/global.saved .config.new && mv .config.new .config; fi; \
			fi; exit 0; \
		fi; \
		board=$$new_board; \
		echo "OpenWrt: regenerating configuration for $$board"; \
	done; echo 'Target System changed repeatedly' >&2; exit 1

prepare:
	@set -eu; mkdir -p $(STATE); \
	command -v flock >/dev/null || { echo "host flock is required for shared build resources" >&2; exit 1; }; \
	board=$$($(CONFIG_TOOL) board .config); \
	$(CONFIG_TOOL) generate "$$board"; \
	$(CONFIG_TOOL) seed .config "$$board" $(STATE)/global.seed; \
	$(call kconfig,$(STATE)/global.resolved) $(CONF) $(KCONF_FLAGS) --defconfig=$(STATE)/global.seed -w $(STATE)/global.resolved $(STATE)/Config.in
	+$(MAKE) -f include/multi-target-config.mk split

ifeq ($(MAKECMDGOALS),split)
MULTI_TARGETS := $(shell $(CONFIG_TOOL) selected $(STATE)/global.resolved)
ifeq ($(strip $(MULTI_TARGETS)),)
$(error No subtarget selected)
endif
.PHONY: $(addprefix split/,$(MULTI_TARGETS))
split: $(addprefix split/,$(MULTI_TARGETS))
	@$(CONFIG_TOOL) verify-all $(MULTI_TARGETS)
$(addprefix split/,$(MULTI_TARGETS)): split/%:
	@mkdir -p tmp/targets/$*/work
	@$(CONFIG_TOOL) split $* $(STATE)/global.resolved $(STATE)/global.seed tmp/targets/$*/seed.config
	@$(call kconfig,tmp/targets/$*/resolved.config) $(CONF) $(KCONF_FLAGS) --defconfig=tmp/targets/$*/seed.config -w tmp/targets/$*/resolved.config Config.in
	@$(CONFIG_TOOL) verify $* tmp/targets/$*/resolved.config
	@$(call replace,tmp/targets/$*/resolved.config,tmp/targets/$*/.config)
	@for f in .targetinfo .config-target.in .config-feeds.in; do ln -sfn "$(TOPDIR)/tmp/$$f" "tmp/targets/$*/work/$$f"; done
	+@$(MAKE) -s -f include/multi-target-resource.mk OPENWRT_MULTI_CONTEXT=$* OPENWRT_CONFIG="$(TOPDIR)/tmp/targets/$*/.config" probe
endif
