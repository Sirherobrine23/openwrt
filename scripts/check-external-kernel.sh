#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Never clean or configure the caller's shared kernel sources in place.
set -eu

source_dir=$1
if [ ! -f "$source_dir/Makefile" ]; then
	echo "Missing external kernel Makefile: $source_dir/Makefile" >&2
	exit 1
fi

source_dir=$(CDPATH= cd "$source_dir" && pwd -P)
if [ -n "${2:-}" ]; then
	output_dir=$(perl -MCwd=abs_path -MFile::Spec -e 'print abs_path($ARGV[0]) // File::Spec->rel2abs($ARGV[0])' "$2")
	case "$source_dir/" in
		"$output_dir/"*) echo "External kernel sources must be outside the output directory: $source_dir" >&2; exit 1 ;;
	esac
	case "$output_dir/" in
		"$source_dir/"*) echo "External kernel outputs must be outside the source directory: $output_dir" >&2; exit 1 ;;
	esac
fi

# Match kbuild: only the selected architecture's generated files matter.
# Without an architecture argument, retain the conservative standalone check.
source_arch=${3:-*}
case "$source_arch" in
	*[!a-zA-Z0-9_-]*)
		[ "$source_arch" = '*' ] || { echo "Invalid kernel architecture: $source_arch" >&2; exit 1; } ;;
esac

for entry in "$source_dir/.config" "$source_dir/include/config" \
	"$source_dir/include/generated" "$source_dir"/arch/$source_arch/include/generated; do
	[ ! -e "$entry" ] && [ ! -L "$entry" ] && continue
	echo "External kernel contains in-tree build files: $entry" >&2
	if [ "$source_arch" = '*' ]; then
		echo "Back up its configuration, then run 'make -C $source_dir ARCH=<architecture> mrproper' for the previously built architectures." >&2
	else
		echo "Back up its configuration, then run 'make -C $source_dir ARCH=$source_arch mrproper'." >&2
	fi
	echo "OpenWrt will keep subsequent kernel outputs in each subtarget build directory." >&2
	exit 1
done
