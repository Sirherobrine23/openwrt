#
# AN7552 Profile
#

define Device/an7552-evb
  $(Device/FitImage)
  DEVICE_VENDOR := Airoha
  DEVICE_MODEL := AN7552 Evaluation Board
endef
TARGET_DEVICES += an7552-evb

define Device/an7563-evb
  $(Device/FitImage)
  DEVICE_VENDOR := Airoha
  DEVICE_MODEL := AN7563 Evaluation Board
endef
TARGET_DEVICES += an7563-evb

define Device/nokia_g-1426g-c
  $(Device/FitImage)
  DEVICE_VENDOR := Nokia
  DEVICE_MODEL := G-1426G-C
  DEVICE_ALT0_VENDOR := Airtel
  DEVICE_ALT0_MODEL := AOT4221NK
  DEVICE_DTS := an7552-nokia_g-1426g-c
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  UBOOTENV_IN_UBI := 1
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  ARTIFACTS := uboot-chainload.itb
  ARTIFACT/uboot-chainload.itb := uboot-chainloader
  DEVICE_PACKAGES := hostapd-mbedtls wpa-supplicant-mbedtls \
                     kmod-mt7915e kmod-mt7916-firmware
endef
TARGET_DEVICES += nokia_g-1426g-c
