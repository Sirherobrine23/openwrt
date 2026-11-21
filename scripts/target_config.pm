# SPDX-License-Identifier: GPL-2.0-only
# Metadata/lexical transformations for the native multi-target Make rules.
# No subprocess builds or Kconfig frontend orchestration here.
package target_config;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Digest::SHA qw(sha256_hex);
use File::Find qw(find);

# Include recipe contents rather than their mtimes. In particular, updating
# a compiler source revision must not reuse an older installed toolchain.
sub recipe_digest {
	my @roots = @_;
	my @files;
	find({no_chdir => 1, wanted => sub {
		push @files, $File::Find::name if -f $_;
	}}, grep {-e $_} @roots);
	my $digest = Digest::SHA->new(256);
	for my $file (sort @files) {
		$digest->add("$file\0");
		open my $fh, '<', $file or die "$file: $!\n";
		$digest->addfile($fh);
	}
	return $digest->hexdigest;
}

# Compiler cache settings change execution, not the resulting host tools or ABI.
sub host_key {
	my ($v) = @_;
	my @names = grep {
		/^(?:HOST_|OPTIMIZE_HOST_TOOLS$|REPRODUCIBLE_DEBUG_INFO$)/
	} keys %$v;
	my $data = join("\n", map {"$_=$v->{$_}"} sort @names);
	$data .= recipe_digest('tools', 'include/host-build.mk', 'include/prereq-build.mk',
		'include/autotools.mk', 'include/cmake.mk', 'include/meson.mk', 'rules.mk');
	for my $driver (['gcc', 'cc'], ['g++', 'c++']) {
		my $configured = "staging_dir/host/bin/$driver->[0]";
		my $cc = -x $configured ? $configured : $driver->[1];
		for my $arg ('-dumpmachine', '--version') {
			open my $fh, '-|', $cc, $arg or die "$cc: $!\n";
			$data .= do {local $/; <$fh>};
			close $fh or die "Cannot identify the host compiler $cc\n";
		}
	}
	return sha256_hex($data);
}

my $state = 'tmp/multi-target';
my %global = map { $_ => 1 } qw(MODULES HAVE_DOT_CONFIG DEVEL BROKEN EXPERIMENTAL BUILDBOT ALL
 ALL_KMODS ALL_NONSHARED SIGNED_PACKAGES SIGNATURE_CHECK DOWNLOAD_CHECK_CERTIFICATE
 USE_APK SIGN_EACH_PACKAGE SIGN_FIRMWARE DOWNLOAD_FOLDER DOWNLOAD_TOOL_CUSTOM
 LOCALMIRROR BINARY_FOLDER JSON_OVERVIEW_IMAGE_INFO JSON_CYCLONEDX_SBOM);
my %kw = map { $_ => 1 } qw(config menuconfig choice endchoice menu endmenu mainmenu
 if endif comment bool tristate string int hex def_bool def_tristate default prompt
 depends on select imply range visible reset optional modules help y m n source);
sub slurp { my ($p)=@_; open my $f, '<', $p or die "$p: $!\n"; local $/; <$f> // '' }
sub write_changed {
 my ($p,$s)=@_; return if -f $p && slurp($p) eq $s;
 make_path(dirname($p)); open my $f,'>',"$p.new" or die "$p.new: $!\n";
 print $f $s; close $f or die "$p.new: $!\n"; rename "$p.new",$p or die "$p: $!\n";
}
sub quote { my $s=shift; $s =~ s/(["\\])/\\$1/g; '"'.$s.'"' }
sub symbol { my $s=shift; $s =~ tr/\/.\- /____/; "TARGET_$s" }
sub prefix { symbol($_[0]).'_' }
sub config {
 my ($p)=@_; my %v; return \%v unless -f $p;
 for (split /\n/,slurp($p)) { if (/^CONFIG_([^=]+)=(.*)$/) { $v{$1}=$2 } elsif (/^# CONFIG_(\S+) is not set$/) { $v{$1}='n' } }
 return \%v;
}
sub serialize { my ($v)=@_; "# OpenWrt configuration\n".join('',map { $v->{$_} eq 'n' ? "# CONFIG_$_ is not set\n" : "CONFIG_$_=$v->{$_}\n" } sort keys %$v) }
my (%meta,@targets);
sub metadata {
 return if @targets;
 my $t;
 for (split /\n/,slurp('tmp/.targetinfo')) {
  if (/^Target: (\S+)$/) { $t=$1; die "invalid target $t\n" unless $t =~ m{^[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)?$}; push @targets,$t; $meta{$t}={} }
  elsif (defined $t && /^(Target-Name|Default-Subtarget|Target-Features|Linux-Version|Linux-Testing-Version|Linux-Release|Linux-Kernel-Arch): (.*)$/) { $meta{$t}{$1}=$2 }
  elsif (defined $t && /^Target-Profile: DEVICE_/) { $meta{$t}{devices}=1 }
 }
 die "empty target metadata\n" unless @targets;
}
sub leaves { my $b=shift; my @l=grep { index($_,"$b/")==0 } @targets; @l ? @l : ($b) }
sub board { my $v=shift; my @b=grep { !m{/} } @targets; my @s=grep { ($v->{symbol($_)}//'') eq 'y' } @b; die "select exactly one board\n" if @s>1; $s[0] // ((grep { $_ eq 'mediatek' } @b)[0] // $b[0]) }
sub device { my ($n,$t)=@_; my $s=substr(symbol($t),7); $n =~ /^TARGET_DEVICE_(?:PACKAGES_)?\Q$s\E_DEVICE_/ }
sub lines {
 my ($text)=@_; my @out; my $pending=''; my $help;
 for my $line (split /(?<=\n)/,$text) {
  if (defined $help) {
   my $x=$line; $x =~ s/^(\s*)/my $p=$1; my $i=0; $i += $_ eq "\t" ? 8-$i%8 : 1 for split '',$p; ' ' x $i/e;
   my ($indent)=$x =~ /^( *)/; my $n=length($indent//'');
   if ($line !~ /\S/) { push @out,[$line,1]; next }
   if ($help<0) { $help=$n||undef }
   if (defined $help && $n >= $help) { push @out,[$line,1]; next }
   undef $help;
  }
  if ($line =~ s/\\\n$//) { $pending.=$line; next }
  $line=$pending.$line; $pending=''; $help=-1 if $line =~ /^\s*(?:help|---help---)\s*$/;
  push @out,[$line,0];
 }
 push @out,[$pending,0] if length $pending;
 @out;
}
sub flatten {
 my ($path,$target,$stack)=@_; die "recursive source: $path\n" if grep { $_ eq $path } @$stack;
 my $text=$path eq 'tmp/.config-target.in' ? $target : slurp($path); my @out;
 for my $pair (lines($text)) {
  my ($line,$help)=@$pair;
  if (!$help && $line =~ /^\s*source\s+"([^"]+)"\s*(?:\#.*)?$/) {
   my $p=$1; die "dynamic source $p\n" if $p =~ /\$/;
   my @p=sort grep {-f $_} glob($p);
   @p=sort grep {-f $_} glob(dirname($path).'/'.$p) unless @p || $p =~ /[*?\[]/;
   die "missing source $p\n" unless @p || $p =~ /[*?\[]/;
   push @out,map { flatten($_,$target,[@$stack,$path]) } @p;
  } else {push @out,$line}
 }
 @out;
}
sub blocks {
 my $text=join('',@_); my (@out,@b);
 for my $p (lines($text)) { my ($l,$h)=@$p;
  if (!$h && $l =~ /^\s*(?:(?:config|menuconfig|choice|endchoice|menu|endmenu|if|endif|comment|mainmenu)\b|[\w.-]+\s*(?::=|\+=|=))/ && @b) { push @out,[@b]; @b=() }
  push @b,$l;
 } push @out,[@b] if @b; @out;
}
sub decl { $_[0][0] =~ /^\s*(?:menuconfig|config)\s+([\w.-]+)\s*$/ ? $1 : '' }
sub prompt { for (@{$_[0]}[1..$#{$_[0]}]) { last if /^\s*(?:help|---help---)\s*$/; return $1 if /^\s*(?:bool|tristate|string|int|hex|prompt)\s+"((?:[^"\\]|\\.)*)"/ } undef }
sub kind { for (@{$_[0]}) { return $1 if /^\s*(bool|tristate)\b/ } 'tristate' }
sub head { my $s=$_[0][0]; $s =~ s/^\s+|\s+$//g; $s }
sub sections {
 my @bs=@_; my (@out,@loose,@cur,@stack); my $title;
 for my $b (@bs) { my $h=head($b);
  if (!@stack && $h =~ /^menu "/) { push @out,['',[@loose]] if @loose; @loose=(); $title=$h }
  if (defined $title) {push @cur,$b} else {push @loose,$b}
  if ($h =~ /^(menu|if|choice)\b/) {push @stack,$1}
  elsif ($h =~ /^end(menu|if|choice)\b/) { my $e=$1; die "unbalanced $h\n" unless @stack && pop(@stack) eq $e }
  if (defined $title && !@stack) {push @out,[$title,[@cur]]; @cur=(); undef $title}
 } die "unbalanced Kconfig\n" if @stack; push @out,['',[@loose]] if @loose; @out;
}
sub menu_body { my $g=shift; my @d=map { /^\s*depends on\s+(.+?)\s*$/ ? "($1)" : () } @{$g->[0]}[1..$#{$g->[0]}]; my @b=@$g[1..$#$g-1]; @d ? (["if ".join(' && ',@d)."\n"],@b,["endif\n"]) : @b }
sub unwrap { my ($title,@s)=@_; map { $_->[0] eq 'menu '.quote($title) ? menu_body($_->[1]) : @{$_->[1]} } @s }
sub tokens { my ($l,$t)=@_; my $p=prefix($t); $l =~ s{("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\$\([^\n]*?\)|\#[^\n]*|[\w.-]+)}{my $x=$1; $x =~ /^["'\#\$0-9]/ || $kw{$x} || $global{$x} || device($x,$t) ? $x : $p.$x}ge; $l }
sub rewrite {
 my ($b,$t,$request,$pkgs)=@_; my $n=decl($b); return '' if $global{$n} || head($b)=~/^mainmenu /;
 if ($pkgs->{$n}) { my $p=prefix($t); my $title=prompt($b); my $s=tokens($b->[0],$t)."\t".kind($b).(defined $title?' '.quote($title):'')."\n";
  $s.="\tdefault $n if $n\n" if exists $request->{$n}; $s.="\tdefault y if ${p}DEFAULT_".substr($n,8)."\n"; return $s }
 my $s=''; for my $x (lines(join('',@$b))) { my ($l,$h)=@$x;
  if ($h || $l =~ /^\s*(?:help|---help---)\s*$/ || $l =~ /^\s*[\w.-]+\s*(?::=|\+=|=)/ || $l !~ /\S/) {$s.=$l; next}
  next if $l =~ /^\s*(?:select|imply)\s+([\w.-]+)(?=\s|$)/ && $pkgs->{$1}; $s.=tokens($l,$t);
 } $s;
}
sub generate {
 my $board=shift; my @leaf=leaves($board); my $orig=slurp('tmp/.config-target.in');
 my (%pkgs,%fields,$entry); for (split /\n/,slurp('tmp/.packageinfo')) { if (/^Package: (\S+)/) {$entry="PACKAGE_$1"; $pkgs{$entry}=1} elsif (defined $entry && /^(Category|Submenu): (.*)$/) {$fields{$entry}{$1}=$2} }
 my @pb=blocks(flatten('tmp/.config-package.in',$orig,[])); my (%request,%pblock,%cat);
 for my $b (@pb) {my $n=decl($b); my $p=prompt($b); next unless $pkgs{$n} && defined $p; $request{$n}=$p; $pblock{$n}=$b;  }
 for my $n (keys %request) { push @{$cat{$fields{$n}{Category}//'Other packages'}{$fields{$n}{Submenu}//''}},$n }
 my %catalog; for my $c (keys %cat) { for my $sub (sort { (!$a)<=> (!$b) || lc($a) cmp lc($b) } keys %{$cat{$c}}) { $catalog{$c}.='menu '.quote($sub)."\n" if $sub; for my $n (sort {lc($a) cmp lc($b)} @{$cat{$c}{$sub}}) {my $b=$pblock{$n}; $catalog{$c}.="config $n\n\t".kind($b).' '.quote($request{$n})."\n"; my $h=0; for my $x (lines(join('',@$b[1..$#$b]))) { if ($x->[0] =~ /^\s*(?:help|---help---)\s*$/) {$h=1} elsif ($h && !$x->[1]) {last} $catalog{$c}.=$x->[0] if $h; }} $catalog{$c}.="endmenu\n" if $sub }}
 my %visible=(%global,map {$_=>1} keys %request); my %opts; my $out="mainmenu \"OpenWrt Configuration\"\n";
 my $globals=sub {my ($g,$devel)=@_; for my $b (@$g) {my $n=decl($b); next unless $global{$n}; my $s=join('',@$b); if ($devel && $n eq 'DEVEL') {$s =~ s/^menuconfig DEVEL\b/config DEVEL/; $s =~ s/Advanced configuration options \(for developers\)/Enable advanced configuration options/} $s =~ s/^\s*(?:imply|select) PACKAGE_\S+.*\n//mg; $out.=$s }};
 my $context=sub {my ($t,$g,$label,$adv)=@_; return unless @$g; $out.='menu '.quote($label//$t)."\n\tdepends on ".symbol($t)."\n"; $out.="\tvisible if DEVEL\n" if $adv;
  for my $b (@$g) {my $n=decl($b); $visible{device($n,$t)||$global{$n}?$n:prefix($t).$n}=1 if $n && defined prompt($b); $opts{prefix($t).$n}=1 if $pkgs{$n}; $out.=rewrite($b,$t,\%request,\%pkgs)} $out.="endmenu\n"; };
 my @header=blocks(grep {!/^\s*source\s+/} split /(?<=\n)/,slurp('Config.in')); $globals->(\@header);
 for (@header) {$out.=join('',@$_) if $_->[0]=~/^\s*[\w.-]+\s*(?::=|\+=|=)/}
 $out.="\nchoice\n\tprompt \"Target System\"\n\tdefault ".symbol($board)."\n";
 for my $t (grep {!m{/}} @targets) {$visible{symbol($t)}=1; $out.='config '.symbol($t)."\n\tbool ".quote($meta{$t}{'Target-Name'}//$t)."\n"; $out.="\tdepends on BROKEN\n" if ($meta{$t}{'Target-Features'}//'') =~ /\bbroken\b/} $out.="endchoice\n";
 if (@leaf!=1 || $leaf[0] ne $board) {$out.="menu \"Subtarget\"\n\tdepends on ".symbol($board)."\n"; my $default=$meta{$board}{'Default-Subtarget'}//(split m{/},$leaf[0])[1]; for my $t (@leaf) {$visible{symbol($t)}=1; $out.='config '.symbol($t)."\n\tbool ".quote($meta{$t}{'Target-Name'}//$t)."\n"; $out.="\tdefault y\n" if (split m{/},$t)[1] eq $default; $out.="\tdepends on BROKEN\n" if ($meta{$t}{'Target-Features'}//'') =~ /\bbroken\b/} $out.="endmenu\n"}
 $out.="menu \"Target Devices\"\n";
 for my $t (@leaf) {open my $f,'-|','scripts/target-metadata.pl','--context',$t,'config','tmp/.targetinfo' or die $!; my $text=do {local $/; <$f>}; close $f or die "target metadata failed\n"; my @g=(@header,unwrap('Target Devices',sections(blocks(flatten('target/Config.in',$text,[]))))); $context->($t,\@g)} $out.="endmenu\n";
 my $group=sub {my ($path,$title)=@_; my @g=unwrap($title,sections(blocks(flatten($path,$orig,[])))); $out.='menu '.quote($title)."\n"; $globals->(\@g); $context->($_,\@g) for @leaf; $out.="endmenu\n"};
 $group->('config/Config-images.in','Target Images');
 my @build=sections(blocks(flatten('config/Config-build.in',$orig,[]))); $globals->($_->[1]) for grep {!$_->[0]} @build;
 $out.="menu \"Global build settings\"\n"; my @bg=unwrap('Global build settings',grep {$_->[0]} @build); $globals->(\@bg); $context->($_,\@bg) for @leaf; $out.="endmenu\n";
 my @dev=blocks(flatten('config/Config-devel.in',$orig,[])); my @tc=blocks(flatten('toolchain/Config.in',$orig,[])); $out.="menu \"Advanced configuration options (for developers)\"\n"; $globals->(\@dev,1); $context->($_,[@dev,@tc],undef,1) for @leaf; $out.="endmenu\n";
 $group->('target/imagebuilder/Config.in','Build the OpenWrt Image Builder'); my @sdk=blocks(flatten('target/sdk/Config.in',$orig,[])); for my $pair (['Build the OpenWrt SDK',[grep {decl($_) ne 'SDK_LLVM_BPF'} @sdk]],['Build the LLVM-BPF toolchain tarball',[grep {decl($_) eq 'SDK_LLVM_BPF'} @sdk]]) {next unless @{$pair->[1]}; $out.='menu '.quote($pair->[0])."\n"; $context->($_,$pair->[1]) for @leaf; $out.="endmenu\n"}
 $group->('target/toolchain/Config.in','Package the OpenWrt-based Toolchain');
 my @ps=sections(@pb); my @loose=map {@{$_->[1]}} grep {!$_->[0]} @ps; if (@loose) {$out.="menu \"Image configuration\"\n"; $context->($_,\@loose) for @leaf; $out.="endmenu\n"}
 for my $s (grep {$_->[0]} @ps) {my ($c)=$s->[0]=~/^menu "(.*)"$/; $out.=$s->[0]."\n".(delete($catalog{$c})//''); my @g=menu_body($s->[1]); $context->($_,\@g,"Package options: $_") for @leaf; $out.="endmenu\n"} for my $c (sort keys %catalog) {$out.='menu '.quote($c)."\n".$catalog{$c}."endmenu\n"}
 write_changed("$state/Config.in",$out); for my $p (['visible',\%visible],['requests',\%request],['package-options',\%opts]) {write_changed("$state/$p->[0]",join('',map {"$_\n"} sort keys %{$p->[1]}))}
}
sub setfile { +{map {$_=>1} split /\n/,slurp("$state/$_[0]")} }
sub migrate {
 my ($v,$b)=@_; my $vis=setfile('visible'); my @sel=grep {($v->{symbol($_)}//'') eq 'y'} leaves($b); my $old=$v->{TARGET_SUBTARGET}//''; $old =~ s/"//g;
 my $t=(grep {$_ eq "$b/$old"} leaves($b)) ? "$b/$old" : undef; $t=$sel[0] if !defined $t && @sel==1;
 my %r=map {$_=>$v->{$_}} grep {$vis->{$_}} keys %$v;
 if (defined $t) {
  my $p=prefix($t);
  my $legacy=exists $v->{TARGET_SUBTARGET} || exists $v->{ARCH} || exists $v->{TARGET_MULTI_PROFILE} || grep {!$vis->{$_} && $vis->{$p.$_}} keys %$v;
  if ($legacy) { for my $n (keys %$v) {$r{$p.$n}//=$v->{$n} if !$global{$n} && $vis->{$p.$n}} }
 } \%r;
}
sub run {
 local @ARGV = @_;
 metadata();
 my $cmd=shift @ARGV // '';
if ($cmd eq 'board') {print board(config(shift @ARGV))."\n"}
elsif ($cmd eq 'generate') {generate(shift @ARGV)}
elsif ($cmd eq 'seed') {my ($in,$b,$out)=@ARGV; write_changed($out,serialize(migrate(config($in),$b)))}
elsif ($cmd eq 'save') {my ($in,$minimal,$out)=@ARGV; my $v=config($in); my $m=config($minimal); my $vis=setfile('visible'); my $opts=setfile('package-options'); my %r=map {$_=>$v->{$_}} grep {$vis->{$_} && (!$opts->{$_} || exists $m->{$_})} keys %$v; write_changed($out,serialize(\%r))}
elsif ($cmd eq 'selected') {my $v=config(shift @ARGV); print join(' ',grep {($v->{symbol($_)}//'') eq 'y'} leaves(board($v)))."\n"}
elsif ($cmd eq 'split') {
 my ($t,$resolved,$seed,$out)=@ARGV; my $v=config($resolved); my $s=config($seed); my $vis=setfile('visible'); my $opts=setfile('package-options'); my $req=setfile('requests'); my $p=prefix($t); my %r;
 for my $n (keys %$v) {next unless $vis->{$n} && !$opts->{$n}; if ($global{$n} || ($req->{$n} && $v->{$n}=~/^[ym]$/) || device($n,$t)) {$r{$n}=$v->{$n}} elsif (index($n,$p)==0) {$r{substr($n,length($p))}=$v->{$n}}}
 for my $n (keys %$s) {$r{substr($n,length($p))}=$s->{$n} if $opts->{$n} && index($n,$p)==0}
 $r{symbol(board($v))}='y'; $r{symbol($t)}='y'; $r{TARGET_MULTI_PROFILE}='y' if $meta{$t}{devices};
 for my $n (qw(DOWNLOAD_FOLDER BINARY_FOLDER EXTERNAL_KERNEL_TREE BUILD_LOG_DIR TARGET_ROOTFS_DIR)) {my $x=$r{$n}//'""'; $x =~ s/^"|"$//g; next if $x eq '' || $x eq 'n'; die "unsupported path $x\n" if $x =~ /[\s#\$\\'"]/; require Cwd; require File::Spec; $x=File::Spec->rel2abs($x); $x.="/$t" if $n eq 'BUILD_LOG_DIR'||$n eq 'TARGET_ROOTFS_DIR'; $r{$n}=quote($x)}
 write_changed($out,serialize(\%r));
}
elsif ($cmd eq 'verify') {my ($t,$path)=@ARGV; my $v=config($path); my ($b,$s)=split m{/},$t; die "Kconfig did not resolve $t\n" unless ($v->{TARGET_BOARD}//'') eq quote($b) && ($v->{TARGET_SUBTARGET}//'') eq quote($s//'generic')}
elsif ($cmd eq 'resource-key') {
 my ($kind,$t,$file)=@ARGV; my $v=config($file);
 if ($kind eq 'host') {print host_key($v)."\n"; return}
 # Cross compiler compatibility includes the kernel headers used by libc,
 # not merely the target triple or GCC version. Equal inputs can be shared
 # across board names as well as subtargets. Firmware kernel overrides are
 # excluded: toolchain/kernel-headers always uses the versioned header source.
 my $m=$meta{$t};
 my @names=grep { /^(?:ARCH(?:_|$)|CPU_|BIG_ENDIAN$|TARGET_(?:SUFFIX|NAME|OPTIMIZATION)$|DEFAULT_TARGET_OPTIMIZATION$|EXTRA_(?:TARGET_ARCH|GCC|BINUTILS|OPTIMIZATION)|GCC|BINUTILS|LIBC|USE_(?:MUSL|GLIBC|MOLD|MIPS16)|MUSL|GLIBC|MIPS64_ABI|SOFT_FLOAT|HAS_(?:FPU|SPE_FPU)|SSP_SUPPORT|SJLJ_EXCEPTIONS|EXTERNAL_TOOLCHAIN|NATIVE_TOOLCHAIN|TOOLCHAIN|LIBGCC|INSTALL_GCC|INSTALL_GFORTRAN|GDB|NASM|NLS$|IPV6$|TESTING_KERNEL$|HOST_|OPTIMIZE_HOST_TOOLS$|PKG_(?:CC_STACKPROTECTOR|FORTIFY_SOURCE|ASLR_PIE|RELRO|DT_RELR|CHECK_FORMAT_SECURITY|FANALYZER)|PACKAGE_libpthread$|DEBUG$|REPRODUCIBLE_DEBUG_INFO$)/ || /^[a-z][a-z0-9_]*$/ } keys %$v;
 my $data=join("\n",map {$_.'='.($m->{$_}//'')} qw(Linux-Version Linux-Testing-Version Linux-Release Linux-Kernel-Arch));
 $data.="\n".join("\n",map {$_.'='.$v->{$_}} sort @names);
 $data .= "\nhost=".host_key($v);
 # Firmware output wrappers do not alter the shared compiler or sysroot.
 $data .= "\nrecipes=".recipe_digest('toolchain', 'include/toolchain-build.mk',
  'include/kernel-version.mk',
  'include/hardening.mk', 'include/quilt.mk', 'target/linux/generic');
 my $key=sha256_hex($data);
 if ($kind eq 'toolchain') { print "$key\n" }
 elsif ($kind eq 'target') { print "$key\n" }
 else {die "unknown resource kind $kind\n"}
}
elsif ($cmd eq 'verify-all') {
 for my $t (@ARGV) {my $v=config("tmp/targets/$t/.config");
  require Cwd; require File::Spec;
  my @paths=map { my ($name,$default)=@$_; my $p=$v->{$name}//'""'; $p =~ s/^"|"$//g; $p=$default if $p eq '' || $p eq 'n'; Cwd::abs_path($p)//File::Spec->rel2abs($p) } (['DOWNLOAD_FOLDER','dl'],['BINARY_FOLDER','bin']);
  die "download and binary directories must be different: $paths[0]\n" if $paths[0] eq $paths[1];
 }
}
else {die "unknown target-config operation: $cmd\n"}
}

1;
