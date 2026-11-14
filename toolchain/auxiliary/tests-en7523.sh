#!/bin/sh
# Smoke-test the installed auxiliary compiler, assembler, linker and header.
set -eu
cross=${1:?Use: sh tests-en7523.sh /absolute/toolchain/bin/riscv64-unknown-elf-}
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT HUP INT TERM
arch=rv32im_zicsr_zifencei_xen7523ops
cat > "$build/test.c" <<'C'
#include <en7523_intrinsics.h>
#ifndef __riscv_xen7523ops
#error missing xen7523ops target macro
#endif
unsigned int set4(unsigned int x) { return en7523_bseti(x, 4); }
unsigned int clear3(unsigned int x) { return en7523_bclri(x, 3); }
int leading(unsigned int x) { return __builtin_clz(x); }
int trailing(unsigned int x) { return __builtin_ctz(x); }
int minimum(int x, int y) { return x < y ? x : y; }
unsigned int field(unsigned int x) { return (x >> 8) & 127; }
int branch(int x) { return x == 7 ? 21 : 42; }
C
"${cross}gcc" -march="$arch" -mabi=ilp32 -O2 -ffreestanding -c "$build/test.c" -o "$build/test.o"
"${cross}ld" -m elf32lriscv -e set4 -Ttext=0x84000000 "$build/test.o" -o "$build/test.elf"
"${cross}objdump" -d -M no-aliases,xen7523ops "$build/test.elf" > "$build/test.dis"
for op in bseti bclri clz ctz min extu; do
 grep -q "en7523\.$op" "$build/test.dis" || { echo "Missing expected opcode: $op" >&2; exit 1; }
done
awk '/^[[:space:]]*[[:xdigit:]]+:/ { if(length($2)!=8 || $3 ~ /^\./) bad=1 } END { exit bad }' "$build/test.dis"
# All functions pulled from libgcc must also avoid compressed instructions.
libgcc=$("${cross}gcc" -march="$arch" -mabi=ilp32 -print-libgcc-file-name)
"${cross}objdump" -d "$libgcc" > "$build/libgcc.dis"
awk '/^[[:space:]]*[[:xdigit:]]+:/ { if(length($2)==4) bad=1 } END { exit bad }' "$build/libgcc.dis" || {
 echo 'libgcc contains compressed instructions; rebuild the rv32im_zicsr_zifencei profile.' >&2; exit 1;
}
printf 'EN7523 GNU smoke test passed: compiler, header, opcodes, linker, RV32IM libgcc.\n'
