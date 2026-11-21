# SPDX-License-Identifier: GPL-2.0-only
# The user-facing goals are the existing OpenWrt goals. Make owns context
# generation, shared resource checks and scheduling; workers use one TOPDIR.
# Keep configuration generation and build dispatch in one transaction. The lock
# lives outside tmp so dirclean cannot replace its inode while it is held.
ifeq ($(OPENWRT_MULTI_LOCKED),)
.DEFAULT_GOAL := world
MULTI_GOALS := $(or $(MAKECMDGOALS),world)
.PHONY: $(MULTI_GOALS) multi-locked
$(MULTI_GOALS): multi-locked
multi-locked:
	+flock $(TOPDIR)/.multi-target.lock $(MAKE) OPENWRT_MULTI_LOCKED=1 $(MULTI_GOALS)
else
ifeq ($(MULTI_TARGET_DISPATCH),1)
TOPDIR ?= $(CURDIR)
MULTI_TARGETS := $(shell ./scripts/target-metadata.pl multi_config selected tmp/multi-target/global.resolved)
ifeq ($(strip $(MULTI_TARGETS)),)
$(error No subtarget selected)
endif
include $(foreach context,$(MULTI_TARGETS),tmp/targets/$(context)/resources.mk)

# Refuse conflicting inputs before a worker can discard a completed shared
# compiler. The native directory must have one identity in this invocation.
define check_native_toolchain
$(eval _native := $(resource.toolchain.$(1)))
$(if $(native_toolchain_owner.$(_native)),\
  $(if $(filter $(key.toolchain.$(1)),$(native_toolchain_key.$(_native))),,\
    $(error Incompatible configurations for $(_native): $(native_toolchain_owner.$(_native)) and $(1); compare their tmp/targets/<context>/.config files)),\
  $(eval native_toolchain_owner.$(_native) := $(1))\
  $(eval native_toolchain_key.$(_native) := $(key.toolchain.$(1))))
endef

# A worker owns the complete shared host/hostpkg graph until it finishes.
# Preserve the jobserver for parallel compilation inside each worker.
.DEFAULT_GOAL := dispatch
.PHONY: dispatch $(addprefix context/,$(MULTI_TARGETS))
dispatch: $(addprefix context/,$(MULTI_TARGETS))

MULTI_READ_ONLY := download check printdb buildinfo diffconfig checksum json_overview_image_info
MULTI_CLEAN := clean targetclean dirclean cacheclean
MULTI_MUTATING := $(filter-out $(MULTI_READ_ONLY) $(MULTI_CLEAN) %/download %/check %/clean val.% var.%,$(MULTI_GOALS))
MULTI_SCOPE := $(if $(filter-out tools/% tools,$(MULTI_MUTATING)),$(if $(filter-out toolchain/% toolchain,$(MULTI_MUTATING)),target,toolchain),host)

ifneq ($(strip $(MULTI_MUTATING)),)
ifneq ($(MULTI_SCOPE),host)
$(foreach context,$(MULTI_TARGETS),$(call check_native_toolchain,$(context)))
endif
endif

define context_rule
context/$(1): $(previous_context)
	$(if $(MULTI_MUTATING),@./scripts/multi-target-state.pl prepare --scope=$(MULTI_SCOPE) --context=$(1) --target=$(resource.target.$(1)) --toolchain=$(resource.toolchain.$(1)) --host-key=$(key.host.$(1)) --toolchain-key=$(key.toolchain.$(1)),@:)
	+$(MAKE) -C $(TOPDIR) \
		OPENWRT_MULTI_CONTEXT=$(1) \
		OPENWRT_CONFIG=$(TOPDIR)/tmp/targets/$(1)/.config \
		GIT_OPTIONAL_LOCKS=0 $(if $(filter download check,$(MULTI_GOALS)),prepare-tmpinfo) $(MULTI_GOALS)
endef
$(foreach context,$(MULTI_TARGETS),$(eval $(call context_rule,$(context)))$(eval previous_context := context/$(context)))
else
.DEFAULT_GOAL := world
MULTI_GOALS := $(or $(MAKECMDGOALS),world)
# Preserve source-tree maintenance and configuration tooling as single global
# operations (rather than running feeds or a Kconfig UI in each worker).
MULTI_PASSTHROUGH := .config prepare-tmpinfo prepare-mk config-clean help distclean \
	package/symlinks package/symlinks-install package/symlinks-clean
MULTI_CONFIG := config defconfig oldconfig menuconfig nconfig xconfig
MULTI_LOCAL := $(filter $(MULTI_PASSTHROUGH) scripts/config/% ./scripts/config/%,$(MULTI_GOALS))
MULTI_CFG_GOALS := $(filter $(MULTI_CONFIG),$(MULTI_GOALS))
MULTI_BUILD_GOALS := $(filter-out $(MULTI_LOCAL) $(MULTI_CFG_GOALS),$(MULTI_GOALS))
.PHONY: $(MULTI_GOALS) multi-local multi-config multi-build
ifneq ($(MULTI_LOCAL),)
$(MULTI_LOCAL): multi-local
multi-local:
	+$(MAKE) OPENWRT_MULTI_INTERNAL=1 $(MULTI_LOCAL)
endif
ifneq ($(MULTI_CFG_GOALS),)
$(MULTI_CFG_GOALS): multi-config
multi-config: $(if $(MULTI_LOCAL),multi-local)
	+$(MAKE) OPENWRT_MULTI_INTERNAL=1 $(MULTI_CFG_GOALS)
endif
ifneq ($(MULTI_BUILD_GOALS),)
$(MULTI_BUILD_GOALS): multi-build
multi-build: $(if $(MULTI_CFG_GOALS),multi-config,$(if $(MULTI_LOCAL),multi-local))
	$(if $(filter %/refresh %/update,$(MULTI_BUILD_GOALS)),$(error Source-changing refresh/update goals are not supported in multi-target builds))
	+@[ -s .config ] || $(MAKE) menuconfig
	+$(MAKE) OPENWRT_MULTI_INTERNAL=1 prepare-tmpinfo scripts/config/conf
	+$(MAKE) -f include/multi-target-config.mk prepare
	+$(MAKE) -f include/multi-target.mk MULTI_TARGET_DISPATCH=1 MULTI_GOALS='$(MULTI_BUILD_GOALS)' dispatch
endif
endif
endif
