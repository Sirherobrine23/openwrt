#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-only
# Exercise native OpenWrt preparation and real kbuild against one local tree.
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);
use Time::HiRes ();
use Test::More;

my ($kernel, $llvm, $keep);
GetOptions('kernel-tree=s' => \$kernel, 'llvm=s' => \$llvm, 'keep' => \$keep) or die "Invalid options\n";
die "Usage: $0 --kernel-tree=/path/to/clean/kernel [--llvm=1|/path/to/llvm/bin/] [--keep]\n" unless $kernel;
$kernel = abs_path($kernel) // die "Missing kernel source\n";
my $source = abs_path("$FindBin::Bin/../..");
die "Kernel paths cannot contain whitespace\n" if $kernel =~ /\s/;
for my $arch (qw(arm mips arm64)) {
	system("$source/scripts/check-external-kernel.sh", $kernel, '', $arch) == 0
		or die "Clean the kernel source for $arch before running this test\n";
}
my $scratch = tempdir(CLEANUP => !$keep);
note "External kernel test outputs: $scratch";
my $log = "$scratch/build.log";

sub put {
	my ($path, $text) = @_;
	open my $fh, '>', $path or die "$path: $!\n";
	print $fh $text;
	close $fh or die $!;
}
sub slurp {
	open my $fh, '<', $_[0] or die "$_[0]: $!\n";
	local $/; <$fh>;
}
sub run {
	my @cmd = @_;
	open my $out, '>&', \*STDOUT or die $!;
	open my $err, '>&', \*STDERR or die $!;
	open STDOUT, '>>', $log or die $!;
	open STDERR, '>&', \*STDOUT or die $!;
	my $status = system(@cmd);
	open STDOUT, '>&', $out or die $!;
	open STDERR, '>&', $err or die $!;
	if ($status) {
		my @lines = split /\n/, slurp($log);
		diag join "\n", @lines[(@lines > 25 ? $#lines - 24 : 0) .. $#lines];
	}
	return $status == 0;
}
sub checked {
	my ($description, @cmd) = @_;
	ok(run(@cmd), $description) or BAIL_OUT("See $log");
}
sub elf_identity {
	my ($file) = @_;
	my $data = slurp($file);
	return '' unless substr($data, 0, 4) eq "\177ELF";
	my $endian = ord(substr($data, 5, 1));
	return join ':', ord(substr($data, 4, 1)), $endian,
		unpack($endian == 1 ? 'v' : 'n', substr($data, 18, 2));
}
my @cases = (
	['en7523', 'arm', 'arm_cortex-a7_musl_eabi', '1:1:40'],
	['an7552', 'arm', 'arm_cortex-a7_musl_eabi', '1:1:40'],
	['en751221', 'mips', 'mips_24kc_musl', '1:2:8'],
	['en751627', 'mips', 'mips_24kc_musl', '1:2:8'],
	['en7528', 'mips', 'mipsel_24kc_musl', '1:1:8'],
	['en7580', 'mips', 'mipsel_24kc_musl', '1:1:8'],
	['an7581', 'arm64', 'aarch64_cortex-a53_musl', '2:1:183'],
	['an7583', 'arm64', 'aarch64_cortex-a53_musl', '2:1:183'],
);
make_path("$scratch/module");
put("$scratch/module/Makefile", "obj-m := shared_source_test.o\n");
put("$scratch/module/shared_source_test.c", <<'MODULE');
#include <linux/module.h>
static int __init shared_source_init(void) { return 0; }
static void __exit shared_source_exit(void) { }
module_init(shared_source_init);
module_exit(shared_source_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Shared kernel source output isolation regression");
MODULE

my ($first_obj, $first_flags);
for my $case (@cases) {
	my ($context, $arch, $native, $elf) = @$case;
	my @flags = ("ARCH=$arch", 'HOSTCC='.($ENV{HOSTCC} // 'gcc'));
	if (defined $llvm) {
		push @flags, "LLVM=$llvm", 'KCFLAGS=-Wno-error=unused-command-line-argument';
	} else {
		my ($triple) = $native =~ /^(arm|mipsel|mips|aarch64)_/;
		my ($cpu, $libc) = $native =~ /^(.*)_(musl.*)$/;
		my @cc = sort glob("$source/staging_dir/toolchain-${cpu}_gcc-*_${libc}/bin/$triple*-gcc");
		unless (@cc) { note "Skipping $context: no native compiler; pass --llvm to use Clang"; next }
		(my $prefix = $cc[0]) =~ s/gcc$//;
		push @flags, "CROSS_COMPILE=$prefix";
	}
	my $build = "$scratch/build_dir/target-$native/linux-airoha_$context";
	my $cfg = "$scratch/$context.config";
	put($cfg, "CONFIG_TARGET_airoha=y\nCONFIG_TARGET_airoha_$context=y\nCONFIG_TARGET_BOARD=\"airoha\"\nCONFIG_ARCH=\"$arch\"\nCONFIG_EXTERNAL_KERNEL_TREE=\"$kernel\"\n");
	my @prepare = ('make', '--no-print-directory', '-s', '-C', "$source/target/linux/airoha",
		"TOPDIR=$source", "OPENWRT_CONFIG=$cfg", "OPENWRT_MULTI_CONTEXT=airoha/$context",
		'TARGET_BUILD=1', "KERNEL_BUILD_DIR=$build", 'KERNEL_MAKE_FLAGS='.join(' ', @flags));
	push @prepare, "BISON_PKGDATADIR=$ENV{BISON_PKGDATADIR}" if $ENV{BISON_PKGDATADIR};
	checked("$context: native OpenWrt prepares a separate output tree", @prepare, 'prepare');
	my ($obj) = grep {-d $_ && !-l $_} glob("$build/linux-*");
	BAIL_OUT("Missing object tree for $context") unless $obj;
	my @make = ('make', '--no-print-directory', '-s', '-j4', '-C', $obj, @flags);
	checked("$context: configure the real shared kernel", @make, 'allnoconfig');
	my @config = ("$kernel/scripts/config", '--file', "$obj/.config", '--enable', 'MODULES', '--set-str', 'LOCALVERSION', "-$context-test");
	if ($arch eq 'mips') {
		push @config, '--enable', 'MIPS_MALTA', '--enable', 'CPU_MIPS32_R2', '--enable', '32BIT';
		push @config, '--enable', ($native =~ /^mipsel/ ? 'CPU_LITTLE_ENDIAN' : 'CPU_BIG_ENDIAN');
		push @config, '--disable', ($native =~ /^mipsel/ ? 'CPU_BIG_ENDIAN' : 'CPU_LITTLE_ENDIAN');
	}
	checked("$context: select independent configuration", @config);
	checked("$context: resolve independent configuration", @make, 'olddefconfig');
	checked("$context: build core object, module tools, dtc and exported headers", @make,
		'modules_prepare', 'init/main.o', 'scripts_dtc', 'headers_install', "INSTALL_HDR_PATH=$obj/user_headers");
	is(elf_identity("$obj/init/main.o"), $elf, "$context: correct architecture and endianness");
	checked("$context: build an external module against this output tree", @make,
		"M=$scratch/module", "MO=$obj/external-module", 'KBUILD_MODPOST_WARN=1', 'modules');
	my $module = slurp("$obj/external-module/shared_source_test.ko");
	like($module, qr/vermagic=[^\0]*\Q$context\E-test/, "$context: module uses its own kernel release");
	my $mtime = (Time::HiRes::stat("$obj/init/main.o"))[9];
	checked("$context: incremental core build succeeds", @make, 'init/main.o');
	is((Time::HiRes::stat("$obj/init/main.o"))[9], $mtime, "$context: unchanged core object is reused");
	unless ($first_obj) { ($first_obj, $first_flags) = ($obj, \@flags) }
}
BAIL_OUT('No compiler was available for any context') unless $first_obj;

# A cloned initramfs output must not retain the original KBUILD_OUTPUT path.
my $clone = "$first_obj-initramfs";
put("$scratch/clone.mk", "LINUX_DIR := $first_obj\nLINUX_SRC_DIR := $kernel\nLINUX_EXTERNAL_BUILD := 1\nCONFIG_EXTERNAL_KERNEL_TREE := \"$kernel\"\nKERNEL_MAKE_FLAGS := ".join(' ', @$first_flags)."\nCP := cp -fpR\ninclude $source/include/kernel-defaults.mk\nclone:\n\t\$(call Kernel/PrepareConfigPerRootfs,$clone)\n");
my $base_config = slurp("$first_obj/.config");
checked('prepare an independent initramfs output using the production macro', 'make', '--no-print-directory', '-s', '-f', "$scratch/clone.mk", 'clone');
like(slurp("$clone/Makefile"), qr/export KBUILD_OUTPUT = \Q$clone\E/, 'initramfs wrapper points at its own output');
is(slurp("$first_obj/.config"), $base_config, 'initramfs preparation preserves the normal kernel configuration');
ok(!-e "$kernel/.config" && !-d "$kernel/include/config", 'shared source tree has no generated configuration');
ok(!-e "$scratch/module/modules.order", 'shared external module sources have no build outputs');
done_testing;
