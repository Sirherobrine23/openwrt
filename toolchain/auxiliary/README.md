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

## EN7523 custom instructions (GCC 14.4.0)

The auxiliary GCC 14.4.0 and Binutils 2.46.1 patch queues add the experimental
`xen7523ops` extension used by EN7523 Wireless Lab. GCC patches are selected
by `AUX_GCC_VERSION`, so they are not applied to GCC 13.4.0 or 15.3.0. The
primary Linux compiler and its patch queues are unchanged.

`en7523_intrinsics.h` is registered as a GCC RISC-V extra header and is
installed automatically by `install-gcc`. Firmware can include it without
copying a header into staging directories manually.

For a single-libgcc EN7523 Lab profile, declare:

```make
PKG_TOOLCHAIN_ARCH:=riscv64
PKG_TOOLCHAIN_TARGET:=riscv64-unknown-elf
PKG_TOOLCHAIN_CPU_TYPE:=rv32im_zicsr_zifencei
PKG_TOOLCHAIN_ABI:=ilp32
PKG_TOOLCHAIN_GCC_VERSION:=14.4.0
```

The compiler and libgcc default to standard RV32IM/Zicsr/Zifencei. The
firmware explicitly adds `_xen7523ops` in its compile flags. This avoids
putting EN7523-only instructions into generic runtime helpers and avoids
linking compressed instructions from an `rv32imac` libgcc into the Lab.
The new profile is separate from the old `rv32imac` installation.

After applying the patch and updating the firmware package declaration,
regenerate package metadata and rebuild this auxiliary profile:

```sh
make defconfig
make toolchain/auxiliary/riscv64-unknown-elf__rv32im_zicsr_zifencei__ilp32__gcc-14.4.0/clean V=s
make -j10 toolchain/auxiliary/riscv64-unknown-elf__rv32im_zicsr_zifencei__ilp32__gcc-14.4.0/compile V=s
```

Toolchain preparation stamps are not automatically invalidated by a newly
added patch. Use the explicit auxiliary clean target when updating an
already-built profile. Do not use `toolchain/gcc/clean` for this purpose;
that refers to the main Linux compiler.

The installed prefix is:

```text
staging_dir/toolchain-riscv64-unknown-elf__rv32im_zicsr_zifencei__ilp32__gcc-14.4.0/
```

Smoke-test it from the OpenWrt root:

```sh
sh toolchain/auxiliary/tests-en7523.sh "$PWD/staging_dir/toolchain-riscv64-unknown-elf__rv32im_zicsr_zifencei__ilp32__gcc-14.4.0/bin/riscv64-unknown-elf-"
```

The test compiles C with the installed header, checks generated custom
instructions and ELF linking, and verifies libgcc has no compressed
instructions. It does not execute the code on hardware.
