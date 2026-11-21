# Multiple subtargets with the native OpenWrt layout

Select a target system and its subtargets with the normal commands:

```sh
make defconfig
make menuconfig
make -j8
```

The frontends read and save the root `.config`. Generated Kconfig descriptions,
effective per-subtarget configurations and scan metadata stay in `tmp/targets/`.
Each effective configuration enables `TARGET_MULTI_PROFILE` for device targets.

## Shared native directories

Build and staging prefixes are exactly the native names. Neither the subtarget
name nor a configuration hash is appended to a resource directory.

| Resource | Directory |
| --- | --- |
| Host tools | `build_dir/host`, `staging_dir/host` |
| Package host tools | `build_dir/hostpkg`, `staging_dir/hostpkg` |
| ARM Cortex-A7 packages | `target-arm_cortex-a7_musl_eabi` |
| Big-endian MIPS 24kc packages | `target-mips_24kc_musl` |
| Little-endian MIPS 24kc packages | `target-mipsel_24kc_musl` |
| AArch64 Cortex-A53 packages | `target-aarch64_cortex-a53_musl` |
| Linux compilers | Native `toolchain-<arch>_<cpu>_gcc-<version>_<libc>` names |
| Secondary compilers | Native compiler profile, including an explicit package variant |

EN7523 and AN7552 share the ARM Cortex-A7 directories. EN751221 and EN751627
share the big-endian MIPS directories. EN7528 and EN7580 share the little-endian
MIPS directories. AN7581 and AN7583 share the AArch64 directories. Other target
systems use the same rule; the board name is not a compiler identity.

One worker completes before the next starts because all workers share host and
hostpkg resources. Parallel compilation inside each worker uses the original
GNU Make jobserver. One top-level lock also prevents a second invocation from
changing configuration or cleaning a resource while it is being used.

Compatibility hashes are stored in stamp files. A changed compiler, libc,
header source or host configuration invalidates the affected native resource
in place. Existing compatible stock directories are adopted. A compiler whose
configure files still refer to a v5 `host_<hash>` prefix is rebuilt in place.

Common package objects are reused when their declared options and effective
compiler inputs match. Changed options, kernel paths or nonshared package
contexts change preparation stamps instead of creating another build directory.
Host package preparation stamps also track their effective inputs. Jobserver
FIFO names and the ccache launcher are excluded from these identities.
Enabling ccache or moving its cache does not invalidate shared host tools or
cross-compilers.

The libc sysroot uses the versioned OpenWrt kernel header source. Per-subtarget
external trees, Git sources and kernel-only flags apply to firmware kernels,
not to the shared sysroot. Changing those settings does not rebuild GCC.
When upgrading from v6, existing native compilers and target objects are adopted
without a blanket cleanup. Legacy header symlinks into firmware sources are
removed without changing their destinations; only missing header sources are
prepared again. Existing exported headers are retained until the native header
recipe runs. Use normal toolchain clean goals if an explicit sysroot replacement
is required.
Before dispatch, configurations requesting the same native compiler prefix must
have the same compiler identity. Conflicts stop before any worker or cleanup,
rather than alternating between destructive rebuilds.

On a subtarget switch, aggregate package/kernel stamps and installation
metadata are refreshed. Compiled common packages and development headers remain
shared. The kernel already has a native `linux-<board>_<subtarget>` subdirectory
inside the shared target prefix. This keeps the kernels separate without
separate `target-*` prefixes. Images and package repositories are published to
their respective subtarget destinations before the next worker runs.

## One external kernel source for several subtargets

All selected subtargets may set `EXTERNAL_KERNEL_TREE` to the same local path.
The source tree is shared; each subtarget uses its normal native kernel object
directory, for example:

| Subtarget | Kernel output |
| --- | --- |
| EN7523 | `build_dir/target-arm_cortex-a7_musl_eabi/linux-airoha_en7523/linux-6.18.55` |
| AN7552 | `build_dir/target-arm_cortex-a7_musl_eabi/linux-airoha_an7552/linux-6.18.55` |
| EN751627 | `build_dir/target-mips_24kc_musl/linux-airoha_en751627/linux-6.18.55` |

OpenWrt initializes each directory with kbuild's `O=` mechanism. Subsequent
kernel and module commands use its generated Makefile. `LINUX_SRC_DIR` refers
to the external sources; `LINUX_DIR` refers to the subtarget's outputs, including
its `.config`, generated headers, module symbol versions and stamps. DTS source
includes come from the shared sources, while dtc and compiled modules come from
the output tree. Kernel userspace tools and the xPON agent use the appropriate
source files or exported UAPI without writing into the shared kernel.

Local source changes are checked by native kbuild on every external kernel build.
Exported UAPI headers are refreshed before userspace packages are compiled.
Kernel clean goals remove only the selected output tree. Initramfs variants have
their own output Makefile and configuration as well.

Kbuild requires a source tree without previous in-tree build outputs. If that
kernel was already compiled in place, back up its configuration and clean it
once before the first build with separate outputs:

```sh
cp /path/to/linux/.config /path/to/linux.before-multi.config
for arch in arm mips arm64; do
    make -C /path/to/linux ARCH="$arch" mrproper
done
```

The preparation check reports in-tree artifacts before deleting any existing
OpenWrt kernel output. Architecture-specific generated files are checked only
for the architecture being built, as in kbuild. It does not clean the source
tree automatically. This
one-time kernel source cleanup does not clean OpenWrt host tools or toolchains.
Uncommitted source edits remain available to every subtarget.

The compiler identity excludes firmware-only output wrappers. Existing v6
compiler and target resources are adopted into the current identity schema,
without a blanket rebuild after installing this update.

Real kbuild regression tests can use the native OpenWrt cross-compilers or LLVM:

```sh
perl scripts/tests/external-kernel.pl --kernel-tree=/path/to/linux
perl scripts/tests/external-kernel.pl --kernel-tree=/path/to/linux --llvm=1
```

They use minimal configurations, prepare native output trees, and build core
objects and external modules for the available architectures. They verify
endianness and per-context module releases, check incremental reuse, and
exercise separate initramfs outputs. They do not
build complete device firmware images. Module tests allow modpost warnings
after `modules_prepare`; they check paths, release strings and object ABI,
not loading modules into a running device kernel.

## Migrating from v5

After applying the multi-target update, run:

```sh
make defconfig
./scripts/multi-target-state.pl cleanup
make menuconfig
make -j8
```

The cleanup command takes the same build-tree lock. It removes recognized v5
host hashes, labelled toolchain/target hashes, per-subtarget target prefixes and
private hostpkg prefixes from both `build_dir` and `staging_dir`. It preserves
native resources and explicit secondary compiler variants such as `__en7523`.
No build directory is renamed: configured absolute paths cannot be relocated
safely by renaming an old v5 directory.

Cleanup and build goals use normal OpenWrt commands. Because the resources are
shared, cleaning a native target or compiler also affects other subtargets using
that resource. Source-changing refresh/update operations remain separate.

## Tests

```sh
perl scripts/tests/multi-target.pl
```

The temporary fixture checks identities, native directory reuse, serialization,
in-place invalidation, metadata handover, legacy cleanup and failure propagation.
A full cross-toolchain and firmware build is a separate integration check.
