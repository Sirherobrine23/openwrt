# Package-selected auxiliary GCC toolchains

This build mechanism is for bare-metal firmware executed by a secondary CPU,
not for OpenWrt Linux userspace packages. It must never replace `TARGET_CC`,
`TARGET_CROSS` or the primary Linux sysroot.

A package declares its requirements **before** including `package.mk`:

```make
PKG_TOOLCHAIN_ARCH:=riscv64
PKG_TOOLCHAIN_TARGET:=riscv64-unknown-elf
PKG_TOOLCHAIN_CPU_TYPE:=rv32im_zicsr_zifencei
PKG_TOOLCHAIN_ABI:=ilp32
PKG_TOOLCHAIN_GCC_VERSION:=14.4.0
PKG_TOOLCHAIN_LIBC:=none
```

The package uses `$(PKG_TOOLCHAIN_CC)`, `$(PKG_TOOLCHAIN_CFLAGS)`,
`$(PKG_TOOLCHAIN_CROSS)` etc. It must explicitly pass the auxiliary compiler
to its firmware build rules; these settings do not override Linux target tools.

The package metadata scanner emits a `Build-Auxiliary-Toolchain` profile and
the package dependency generator attaches the matching
`toolchain/auxiliary/<profile>/compile` target. GCC and Binutils build under
`build_dir/toolchain-<profile>` and install to
`staging_dir/toolchain-<profile>` (including their stamps). The same profile is
reused by different packages in a single make invocation.

The current implementation supports `riscv64-unknown-elf` as a compiler target
with a RV32 `-march`, `ilp32`, no libc, GCC 13.4.0/14.4.0/15.3.0, and
Binutils 2.46.1. Different ISA choices produce different toolchains because
multilib is disabled. GCC's libgcc is built for the requested ISA/ABI.

For example, given a package profile of
`riscv64-unknown-elf__rv32imac__ilp32__gcc-14.4.0`:

```sh
make defconfig
make -j10 package/feeds/npu/openwrt-pkg/compile V=s
make toolchain/auxiliary/riscv64-unknown-elf__rv32imac__ilp32__gcc-14.4.0/clean V=s
```

Do not run `make -j10 package/.../{clean,compile}`: those are independent
make goals and may run concurrently. Use two commands separated by `&&`.

The initial implementation does not cover Linux auxiliary sysroots, newlib,
external toolchains or SDK export. It also does not turn auxiliary toolchains
into the default toolchain required by all OpenWrt targets.
