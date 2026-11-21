#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-only
# Exercise resource identity and GNU Make scheduling without a firmware build.
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

my $source = abs_path("$FindBin::Bin/../..");
my $scratch = tempdir(CLEANUP => 1);
chdir $scratch or die $!;
make_path(qw(tmp scripts toolchain tools include target/linux/generic));
for my $name (qw(target-metadata.pl target_config.pm metadata.pm multi-target-state.pl check-external-kernel.sh)) {
	copy("$source/scripts/$name", "scripts/$name") or die $!;
}
chmod 0755, 'scripts/target-metadata.pl', 'scripts/multi-target-state.pl', 'scripts/check-external-kernel.sh';

sub put {
	my ($path, $text) = @_;
	open my $fh, '>', $path or die "$path: $!";
	print $fh $text;
	close $fh or die $!;
}

my @contexts = qw(airoha/en751221 airoha/en751627 airoha/en7528 airoha/en7580);
put('tmp/.targetinfo', join('', map {
	"Target: $_\nTarget-Name: $_\nLinux-Version: 6.18.55\nLinux-Kernel-Arch: mips\n"
} ('airoha', @contexts)));
put('toolchain/Makefile', "# compiler recipe\n");
put('tools/Makefile', "# host recipe\n");
put('target/linux/generic/kernel-6.18', "LINUX_VERSION-6.18 = .55\n");

sub config {
	my ($name, @extra) = @_;
	put($name, join("\n", 'CONFIG_TARGET_airoha=y', 'CONFIG_ARCH="mips"',
		'CONFIG_CPU_TYPE="24kc"', 'CONFIG_GCC_VERSION="14.4.0"',
		'CONFIG_USE_MUSL=y', 'CONFIG_LIBC="musl"', @extra)."\n");
}

sub key {
	my ($kind, $context, $file) = @_;
	open my $fh, '-|', $^X, 'scripts/target-metadata.pl', 'multi_config',
		'resource-key', $kind, $context, $file or die $!;
	my $value = do {local $/; <$fh>};
	close $fh or die "Resource probe failed";
	chomp $value;
	return $value;
}

config('a.config', 'CONFIG_TARGET_airoha_en751221=y');
config('b.config', 'CONFIG_TARGET_airoha_en751627=y', 'CONFIG_PACKAGE_busybox=y');
my $host = key('host', $contexts[0], 'a.config');
my $tc = key('toolchain', $contexts[0], 'a.config');
like($host, qr/^[0-9a-f]{64}$/, 'host identity is a full SHA256');
is(key('host', $contexts[1], 'b.config'), $host, 'host tools ignore target/package selection');
is(key('toolchain', $contexts[1], 'b.config'), $tc, 'compatible subtargets reuse a compiler');
is(key('target', $contexts[0], 'a.config'), key('target', $contexts[1], 'b.config'),
	'compatible subtargets share the native target directory');
config('little.config', 'CONFIG_ARCH="mipsel"', 'CONFIG_mipsel=y');
isnt(key('toolchain', $contexts[2], 'little.config'), $tc, 'different endianness separates compilers');
is(key('host', $contexts[2], 'little.config'), $host, 'native tools remain shared across target architectures');
# A launcher and its storage directory must not wipe shared host/compiler caches.
config('cache.config', 'CONFIG_CCACHE=y', 'CONFIG_CCACHE_DIR="/alternate/cache"');
is(key('host', $contexts[1], 'cache.config'), $host, 'ccache settings do not change host compatibility');
is(key('toolchain', $contexts[1], 'cache.config'), $tc, 'ccache settings do not change compiler compatibility');
config('flags.config', 'CONFIG_EXTRA_GCC_CONFIG_OPTIONS="--disable-libquadmath"');
isnt(key('toolchain', $contexts[0], 'flags.config'), $tc, 'compiler flags invalidate compiler identity');
config('host.config', 'CONFIG_HOST_EXTRA_CFLAGS="-O0"');
isnt(key('host', $contexts[0], 'host.config'), $host, 'host flags invalidate host identity');
isnt(key('toolchain', $contexts[0], 'host.config'), $tc, 'host identity participates in compiler identity');
config('kernel.config', 'CONFIG_KERNEL_GIT_REF="different-headers"');
is(key('toolchain', $contexts[0], 'kernel.config'), $tc, 'firmware Git revision does not change the common sysroot');
config('external.config', 'CONFIG_EXTERNAL_KERNEL_TREE="/firmware/kernel"',
	'CONFIG_KERNEL_GIT_CLONE_URI="https://example.invalid/kernel.git"', 'CONFIG_KERNEL_CFLAGS="-DDEVICE_KERNEL"');
is(key('toolchain', $contexts[1], 'external.config'), $tc, 'external firmware kernels share the common compiler and headers');
make_path('common-kernel');
put('common-kernel/Makefile', "VERSION = 6\nPATCHLEVEL = 18\nSUBLEVEL = 55\nEXTRAVERSION =\n");
for my $context (@contexts) {
	make_path("tmp/targets/$context");
	put("tmp/targets/$context/.config", 'CONFIG_EXTERNAL_KERNEL_TREE="'.$scratch.'/common-kernel"'."\n");
}
is(system($^X, 'scripts/target-metadata.pl', 'multi_config', 'verify-all', @contexts),
	0, 'several contexts may share the same external kernel source');
is(system('scripts/check-external-kernel.sh', "$scratch/common-kernel"), 0, 'clean shared sources pass the preparation check');
make_path('common-kernel/arch/x86/include/generated');
is(system('scripts/check-external-kernel.sh', "$scratch/common-kernel", '', 'mips'), 0,
	'unrelated x86 generated files do not block a MIPS output build');
isnt(system('scripts/check-external-kernel.sh', "$scratch/common-kernel", '', 'x86'), 0,
	'generated files for the selected architecture still block the build');
rmdir 'common-kernel/arch/x86/include/generated' or die $!;
put('common-kernel/.config', "preserve caller configuration\n");
isnt(system('scripts/check-external-kernel.sh', "$scratch/common-kernel"), 0, 'in-tree build state is reported before using O=');
is(do {open my $fh, '<', 'common-kernel/.config' or die $!; local $/; <$fh>},
	"preserve caller configuration\n", 'source checks preserve the caller configuration');
unlink 'common-kernel/.config';

config('analyzer.config', 'CONFIG_PKG_FANALYZER=y');
isnt(key('toolchain', $contexts[0], 'analyzer.config'), $tc, 'libc hardening options participate in identity');
make_path('target/linux/generic/hack-6.18');
put('target/linux/generic/hack-6.18/uapi.patch', "# changed exported kernel headers\n");
isnt(key('toolchain', $contexts[0], 'a.config'), $tc, 'generic kernel header patches invalidate compiler identity');
unlink 'target/linux/generic/hack-6.18/uapi.patch';
put('toolchain/Makefile', "# updated compiler source revision\n");
isnt(key('toolchain', $contexts[0], 'a.config'), $tc, 'recipe changes invalidate installed compiler identity');
put('tools/Makefile', "# updated native library\n");
isnt(key('host', $contexts[0], 'a.config'), $host, 'host recipe changes invalidate native dependencies');
is(system('env', 'OPENWRT_MULTI_CONTEXT=airoha/en751627', 'sh',
	"$source/scripts/check-toolchain-clean.sh"), 0, 'multi-target version check defers to resource identity');
ok(!-e '.toolchain_build_ver', 'per-context version check does not reset a shared compiler');

put('probe.mk', "TOPDIR := $scratch\ninclude $source/include/build-context.mk\n".
	"probe:\n\t\@echo '\$(OPENWRT_HOST_NAME) \$(call package_toolchain_dirname,riscv-profile,compiler-hash)'\n".
	"hostpkg:\n\t\@echo '\$(OPENWRT_HOSTPKG_NAME)'\n");
sub secondary_prefix {
	open my $fh, '-|', 'make', '--no-print-directory', '-s', '-f', 'probe.mk', @_, 'probe' or die $!;
	my $result = do {local $/; <$fh>};
	close $fh or die "Secondary compiler prefix probe failed";
	return $result;
}
my $secondary = secondary_prefix('OPENWRT_MULTI_CONTEXT=airoha/en751221', 'OPENWRT_HOST_DIR_NAME=host-shared');
is(secondary_prefix('OPENWRT_MULTI_CONTEXT=airoha/en751627', 'OPENWRT_HOST_DIR_NAME=host-shared'),
	$secondary, 'secondary compilers share a prefix across compatible contexts');
is(secondary_prefix('OPENWRT_MULTI_CONTEXT=airoha/en751627', 'OPENWRT_HOST_DIR_NAME=host-other'),
	$secondary, 'host settings cannot create alternate secondary compiler prefixes');
is(secondary_prefix(), "host toolchain-riscv-profile\n", 'stock and SDK builds retain native host and secondary compiler names');
sub package_host_prefix {
	open my $fh, '-|', 'make', '--no-print-directory', '-s', '-f', 'probe.mk', @_, 'hostpkg' or die $!;
	my $result = do {local $/; <$fh>};
	close $fh or die "Package host prefix probe failed";
	return $result;
}
my $hostpkg = package_host_prefix('OPENWRT_MULTI_CONTEXT=airoha/en751221', 'OPENWRT_HOST_DIR_NAME=host-shared');
is(package_host_prefix('OPENWRT_MULTI_CONTEXT=airoha/en751221', 'OPENWRT_HOST_DIR_NAME=host-other'),
	$hostpkg, 'host settings cannot change the native hostpkg name');
is(package_host_prefix('OPENWRT_MULTI_CONTEXT=airoha/en751627', 'OPENWRT_HOST_DIR_NAME=host-shared'),
	$hostpkg, 'package host builds use the same hostpkg prefix for every subtarget');
is(package_host_prefix(), "hostpkg\n", 'stock and SDK builds retain the native package host prefix');

put('tmp/multi-target-config', join('', map {my $s = $_; $s =~ s{/}{_}g; "CONFIG_TARGET_$s=y\n"} ('airoha', @contexts)));
make_path('tmp/multi-target');
copy('tmp/multi-target-config', 'tmp/multi-target/global.resolved') or die $!;
for my $i (0 .. $#contexts) {
	my $context = $contexts[$i];
	my $arch = $i < 2 ? 'mips' : 'mipsel';
	make_path("tmp/targets/$context");
	put("tmp/targets/$context/resources.mk", join('',
		"resource.host.$context := host\nkey.host.$context := $host\n",
		"resource.toolchain.$context := toolchain-$arch\nkey.toolchain.$context := ${\($i < 2 ? ('1' x 64) : ('2' x 64))}\n",
		"resource.target.$context := target-$arch\nkey.target.$context := key-$context\n"));
}
# Every worker shares native host/hostpkg, even across architectures.
put('worker', <<'WORKER');
#!/usr/bin/env perl
use strict;
use warnings;
my %args = map {split /=/, $_, 2} grep {/=/} @ARGV;
my $context = $args{OPENWRT_MULTI_CONTEXT};
die "Unexpected directory override\n" if grep {/^OPENWRT_(?:HOST|TARGET|TOOLCHAIN)_DIR_NAME$/} keys %args;
mkdir 'busy-host' or die "Concurrent access to native host/hostpkg\n";
open my $out, '>>', 'workers.log' or die $!;
print $out "$context native host hostpkg\n";
close $out;
select undef, undef, undef, 0.05;
rmdir 'busy-host' or die $!;
exit 0;
WORKER
chmod 0755, 'worker';
my @dispatch = ('make', '--no-print-directory', '-s', '-j4', '-f', "$source/include/multi-target.mk",
	'OPENWRT_MULTI_LOCKED=1', 'MULTI_TARGET_DISPATCH=1', 'MULTI_GOALS=world',
	"TOPDIR=$scratch", "MAKE=$scratch/worker", 'dispatch');
is(system(@dispatch), 0, 'parallel make serializes all workers sharing native host/hostpkg');
open my $log, '<', 'workers.log' or die $!;
my @workers = <$log>;
close $log;
is(scalar @workers, 4, 'all requested subtargets ran');
my %seen_host = map {(split /\s+/)[2] => 1} @workers;
is(scalar keys %seen_host, 1, 'all compatible workers receive one host prefix');
my @before = @workers;
unlink 'workers.log';
is(system(@dispatch), 0, 'incremental dispatch succeeds');
open $log, '<', 'workers.log' or die $!;
my @after = <$log>;
close $log;
is_deeply([sort @after], [sort @before], 'resource allocation is stable across invocations');

# Native stock directories are adopted, not duplicated with hashed names.
make_path('build_dir/toolchain-mips');
put('build_dir/toolchain-mips/stock-file', "preserve me\n");
unlink 'workers.log';
is(system(@dispatch), 0, 'dispatch reuses an existing native toolchain');
ok(-f 'build_dir/toolchain-mips/stock-file', 'compatible native toolchain contents are preserved');
ok(!glob('build_dir/toolchain-mips_*'), 'no hashed toolchain directories are allocated');
ok(!glob('build_dir/host_*'), 'no hashed host directories are allocated');
ok(!glob('staging_dir/target-mips_*'), 'no per-subtarget staging prefixes are allocated');

sub prepare_native {
	my ($which, $compiler_key, $native_host_key) = @_;
	return system($^X, 'scripts/multi-target-state.pl', 'prepare', '--scope=target',
		"--context=$which", '--target=target-mips', '--toolchain=toolchain-mips',
		"--host-key=".($native_host_key // $host), "--toolchain-key=$compiler_key");
}
my $compatible_key = '1' x 64;
# Migrating the signature must preserve compiled resources and external trees.
put('staging_dir/toolchain-mips/stamp/.multi-target-key', ('0' x 64)."\n");
put('staging_dir/toolchain-mips/stamp/.multi-target-key-v2', ('0' x 64)."\n");
unlink 'staging_dir/toolchain-mips/stamp/.multi-target-key-v3';
put('staging_dir/target-mips/stamp/.multi-target-key', ('0' x 64)."\n");
put('staging_dir/target-mips/stamp/.multi-target-key-v2', ('0' x 64)."\n");
unlink 'staging_dir/target-mips/stamp/.multi-target-key-v3';
make_path('build_dir/target-mips');
put('build_dir/target-mips/preexisting-object', "retain target objects\n");
make_path('firmware-kernel');
put('firmware-kernel/.config', "external kernel configuration\n");
symlink "$scratch/firmware-kernel", 'build_dir/toolchain-mips/linux-6.18.55' or die $!;
is(prepare_native($contexts[0], $compatible_key), 0, 'adopt an existing v6 compiler without cleaning it');
ok(-f 'build_dir/toolchain-mips/stock-file', 'v6 compiler objects survive the signature upgrade');
ok(-f 'build_dir/target-mips/preexisting-object', 'v6 target objects survive the signature upgrade');
ok(!-l 'build_dir/toolchain-mips/linux-6.18.55', 'detach the legacy external header symlink');
is(do {open my $fh, '<', 'firmware-kernel/.config' or die $!; local $/; <$fh>},
	"external kernel configuration\n", 'the external firmware source is untouched');

is(prepare_native($contexts[0], $compatible_key), 0, 'prepare the first native target context');
make_path('build_dir/target-mips/common-package', 'staging_dir/target-mips/pkginfo',
	'staging_dir/target-mips/usr/include', 'build_dir/target-mips/linux-airoha_en751221',
	'build_dir/target-mips/linux-airoha_en751627');
put('build_dir/target-mips/common-package/.built', "compiled once\n");
put('staging_dir/target-mips/pkginfo/previous.install', "previous package\n");
put('staging_dir/target-mips/usr/include/common.h', "shared header\n");
put('staging_dir/target-mips/stamp/.package_compile', "old graph\n");
put('staging_dir/target-mips/stamp/.target_compile', "old kernel graph\n");
put('build_dir/target-mips/linux-airoha_en751221/kernel', "first kernel\n");
put('build_dir/target-mips/linux-airoha_en751627/kernel', "second kernel\n");
is(prepare_native($contexts[1], $compatible_key), 0, 'switch a compatible subtarget in the native prefix');
ok(-f 'build_dir/target-mips/common-package/.built', 'compiled common packages survive a context switch');
ok(-f 'staging_dir/target-mips/usr/include/common.h', 'development headers are shared');
ok(!-f 'staging_dir/target-mips/pkginfo/previous.install', 'package installation metadata is refreshed');
ok(!-f 'staging_dir/target-mips/stamp/.package_compile', 'the package graph is revisited');
ok(!-f 'staging_dir/target-mips/stamp/.target_compile', 'the correct kernel graph is revisited');
ok(-f 'build_dir/target-mips/linux-airoha_en751221/kernel' &&
	-f 'build_dir/target-mips/linux-airoha_en751627/kernel', 'kernel trees coexist inside one native target prefix');
is(prepare_native($contexts[1], 'e' x 64), 0, 'changed compiler inputs rebuild the native toolchain in place');
ok(!-f 'build_dir/toolchain-mips/stock-file', 'incompatible compiler objects are discarded');
ok(!-f 'build_dir/target-mips/common-package/.built', 'incompatible target objects are discarded');
ok(!glob('staging_dir/toolchain-mips_*'), 'invalidation never creates an alternate compiler prefix');
make_path('build_dir/host', 'build_dir/hostpkg');
put('build_dir/host/native-tool', "old flags\n");
put('build_dir/hostpkg/native-tool', "old dependencies\n");
is(prepare_native($contexts[1], 'e' x 64, 'f' x 64), 0, 'changed host flags reuse the native host name');
ok(!-f 'build_dir/host/native-tool' && !-f 'build_dir/hostpkg/native-tool', 'host and hostpkg caches are invalidated together');

# A migrated v5 compiler must not retain configure paths to host_<hash>.
make_path('build_dir/toolchain-mips');
unlink 'staging_dir/toolchain-mips/stamp/.multi-target-key-v3';
put('build_dir/toolchain-mips/Makefile', "GMP=/tree/staging_dir/host_0123456789abcdef\n");
is(prepare_native($contexts[1], 'e' x 64, 'f' x 64), 0, 'v5 host paths are detected when adopting a native compiler');
ok(!-f 'build_dir/toolchain-mips/Makefile', 'a compiler tied to v5 host paths is rebuilt');

make_path('staging_dir/.build-contexts');
my @obsolete = ('host_0123456789abcdef', 'hostpkg_airoha_en751627',
	'target-mips_airoha_en751627', 'toolchain-mips_0123456789abcdef',
	'toolchain-riscv-profile_'.('a' x 32).'_host_0123456789abcdef');
for my $name (@obsolete) {
	make_path("build_dir/$name", "staging_dir/$name");
	put("staging_dir/.build-contexts/$name", ('a' x 64)."\n");
}
make_path('build_dir/toolchain-riscv-profile__en7523');
put('build_dir/toolchain-riscv-profile__en7523/native-variant', "keep this variant\n");
is(system($^X, 'scripts/multi-target-state.pl', 'cleanup'), 0, 'remove obsolete v5 directory forms');
ok(!grep({-e "build_dir/$_" || -e "staging_dir/$_"} @obsolete), 'obsolete prefixes are removed from both native roots');
ok(-f 'build_dir/toolchain-riscv-profile__en7523/native-variant', 'explicit secondary compiler variants are preserved');
ok(-d 'staging_dir/toolchain-mips' && -d 'staging_dir/host', 'native resource prefixes are preserved');

# Reject a mismatched shared compiler before starting any worker or cleanup.
my $resources = "tmp/targets/$contexts[1]/resources.mk";
my $resource_text = do {open my $fh, '<', $resources or die $!; local $/; <$fh>};
put($resources, $resource_text."key.toolchain.$contexts[1] := ".('3' x 64)."\n");
make_path('build_dir/toolchain-mips');
put('build_dir/toolchain-mips/preserve-before-dispatch', "completed compiler\n");
unlink 'workers.log';
isnt(system(@dispatch), 0, 'conflicting shared compiler inputs fail before dispatch');
ok(!-e 'workers.log', 'no worker starts with conflicting shared compiler inputs');
ok(-f 'build_dir/toolchain-mips/preserve-before-dispatch', 'preflight preserves the completed compiler');
put($resources, $resource_text);

# A failed architecture owner must prevent its dependent worker from running.
put('worker', "#!/bin/sh\nexit 7\n");
isnt(system(@dispatch), 0, 'worker failures propagate to the caller');
chdir $source or die $!;
done_testing;
