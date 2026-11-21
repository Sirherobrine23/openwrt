#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-only
# Native resource identities live in stamps, never in directory names.
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Find qw(find);
use Getopt::Long qw(GetOptions);
use Fcntl qw(LOCK_EX);

my $operation = shift @ARGV // '';
my ($context, $target, $toolchain, $host_key, $toolchain_key, $scope);
GetOptions('context=s' => \$context, 'target=s' => \$target,
	'toolchain=s' => \$toolchain, 'host-key=s' => \$host_key,
	'toolchain-key=s' => \$toolchain_key, 'scope=s' => \$scope) or die "Invalid options\n";

sub read_stamp {
	my ($path) = @_;
	return '' unless -f $path;
	open my $fh, '<', $path or die "$path: $!\n";
	my $value = do { local $/; <$fh> };
	$value =~ s/\s+$//;
	return $value;
}
sub write_stamp {
	my ($path, $value) = @_;
	return if read_stamp($path) eq $value;
	(my $parent = $path) =~ s{/[^/]+$}{};
	make_path($parent);
	open my $fh, '>', "$path.new" or die "$path.new: $!\n";
	print $fh "$value\n";
	close $fh or die "$path.new: $!\n";
	rename "$path.new", $path or die "$path: $!\n";
}
sub drop_prefix {
	my ($name) = @_;
	for my $root ('build_dir', 'staging_dir') {
		my $path = "$root/$name";
		if (-l $path) { unlink $path or die "$path: $!\n" }
		elsif (-d $path) { remove_tree($path, {error => \my $errors}); die "Cannot remove $path\n" if @$errors }
	}
}
sub old_host_paths {
	my ($prefix) = @_;
	return 0 unless -d $prefix;
	my $found = 0;
	find({no_chdir => 1, wanted => sub {
		return if $found || !-f $_ || !m{(?:^|/)Makefile$};
		open my $fh, '<', $_ or die "$_: $!\n";
		while (<$fh>) { if (m{staging_dir/host(?:pkg)?_[A-Za-z0-9]}) { $found = 1; last } }
	}}, $prefix);
	return $found;
}

if ($operation eq 'cleanup') {
	open my $lock, '>>', '.multi-target.lock' or die ".multi-target.lock: $!\n";
	flock($lock, LOCK_EX) or die "Cannot lock the build tree: $!\n";
	# Only remove v5 directory forms. Explicit package toolchain variants such
	# as __en7523 do not match these forms and remain untouched.
	my @suffixes;
	if (open my $fh, '<', 'tmp/.targetinfo') {
		while (<$fh>) { if (/^Target: (\S+)\/(\S+)$/) { push @suffixes, "${1}_${2}" } }
	}
	my %obsolete;
	for my $root ('build_dir', 'staging_dir') {
		next unless -d $root;
		opendir my $dh, $root or die "$root: $!\n";
		for my $name (readdir $dh) {
			my $legacy = $name =~ /^host_[0-9a-f]{16}$/;
			$legacy ||= $name =~ /^(?:target|toolchain)-.*_[0-9a-f]{16}$/ &&
				read_stamp("staging_dir/.build-contexts/$name") =~ /^[0-9a-f]{64}$/;
			for my $suffix (@suffixes) {
				$legacy ||= $name =~ /^hostpkg_\Q$suffix\E(?:_[0-9a-f]{16})?$/;
				$legacy ||= $name =~ /^target-.*_\Q$suffix\E$/ &&
					read_stamp("staging_dir/.build-contexts/$name") =~ /^[0-9a-f]{64}$/;
			}
			# v5 secondary compilers appended a configuration hash and host.
			$legacy ||= $name =~ /^toolchain-.*_[0-9a-f]{32}_host(?:_[0-9a-f]{16})?$/;
			$obsolete{$name} = 1 if $legacy;
		}
		closedir $dh;
	}
	for my $name (sort keys %obsolete) {
		print "Removing obsolete multi-target resource: $name\n";
		drop_prefix($name);
		unlink "staging_dir/.build-contexts/$name";
	}
	exit 0;
}
die "Expected prepare or cleanup\n" unless $operation eq 'prepare';
die "Invalid context\n" unless ($context // '') =~ m{^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?$};
die "Invalid target prefix\n" unless ($target // '') =~ /^target-[A-Za-z0-9_.+-]+$/;
die "Invalid toolchain prefix\n" unless ($toolchain // '') =~ /^toolchain-[A-Za-z0-9_.+-]+$/;
die "Invalid resource key\n" unless ($host_key // '') =~ /^[0-9a-f]{64}$/ && ($toolchain_key // '') =~ /^[0-9a-f]{64}$/;
die "Invalid scope\n" unless ($scope // '') =~ /^(?:host|toolchain|target)$/;

my $host_stamp = 'staging_dir/host/stamp/.multi-target-key';
my $previous = read_stamp($host_stamp);
if ($previous ne '' && $previous ne $host_key) {
	print "Host configuration changed; rebuilding native host resources\n";
	drop_prefix('host');
	drop_prefix('hostpkg');
}
write_stamp($host_stamp, $host_key);
exit 0 if $scope eq 'host';

# Adopt v6 resources once without interpreting firmware build rules as an ABI
# change. A bookkeeping upgrade must not throw away a completed compiler.
my $compiler_stamp = "staging_dir/$toolchain/stamp/.multi-target-key-v3";
$previous = read_stamp($compiler_stamp);
if (($previous ne '' && $previous ne $toolchain_key) ||
	($previous eq '' && old_host_paths("build_dir/$toolchain"))) {
	print "Toolchain configuration changed; rebuilding $toolchain in place\n";
	drop_prefix($toolchain);
	drop_prefix($target);
	drop_prefix('hostpkg');
}
write_stamp($compiler_stamp, $toolchain_key);

# Old header builds could point straight into a firmware source tree.
# Detach that symlink only; preserve the compiler and installed sysroot.
# The native headers recipe can then prepare its own source on demand.
for my $path (glob("build_dir/$toolchain/linux-*")) {
	next unless -l $path && $path =~ m{/linux-[0-9]};
	unlink $path or die "$path: $!\n";
}

my $target_stamp = "staging_dir/$target/stamp/.multi-target-key-v3";
$previous = read_stamp($target_stamp);
if ($previous ne '' && $previous ne $toolchain_key) {
	drop_prefix($target);
}
write_stamp($target_stamp, $toolchain_key);
exit 0 if $scope eq 'toolchain';

my $context_stamp = "staging_dir/$target/stamp/.multi-target-context";
$previous = read_stamp($context_stamp);
if ($previous ne $context) {
	# Revisit the native package graph and regenerate installation metadata.
	# Keep compatible package objects and installed development headers.
	unlink glob("staging_dir/$target/stamp/.target_*"),
		glob("staging_dir/$target/stamp/.package_*"),
		glob("staging_dir/$target/stamp/.*_installed");
	remove_tree("staging_dir/$target/pkginfo");
	for my $cfg (glob('tmp/targets/*/*/.config')) {
		(my $work = $cfg) =~ s{\.config$}{work};
		unlink "$work/.packageauxvars", "$work/.packagedeps";
	}
}
write_stamp($context_stamp, $context);
