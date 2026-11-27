REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN='fitblk fit_check_sign yafut'

platform_do_upgrade() {
  local board=$(board_name)

  case "$board" in
  nokia,g-1426g-c)
    CI_KERNPART="kernel"
    CI_UBIPART="data"
    # Stock firmware fills the "data" UBI with a single "data" volume,
    # leaving no room for rootfs. Drop it on first install.
    local ubidev="$(nand_find_ubi "$CI_UBIPART")"
    [ -n "$ubidev" ] && [ -n "$(nand_find_volume "$ubidev" data)" ] && \
      ubirmvol "/dev/$ubidev" -N data
    nand_do_upgrade "$1"
    ;;
  *)
    nand_do_upgrade "$1"
    ;;
  esac
  sync
}

platform_check_image() {
  local board=$(board_name)
  [ "$#" -gt 1 ] && return 1

  return 0
}
