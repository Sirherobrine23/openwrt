TRX_ENDIAN := be

define Device/zyxel_ex3301-t0
  $(Device/tcboot_trx)
  DEVICE_VENDOR := Zyxel
  DEVICE_MODEL := EX3301-T0
  DEVICE_DTS := en751627_zyxel_ex3301-t0
  IMAGES := tclinux.trx
  IMAGE/tclinux.trx := append-kernel | lzma | tclinux-trx
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7915-firmware
endef
TARGET_DEVICES += zyxel_ex3301-t0

define Device/zyxel_vmg8623-t50b
  $(Device/FitVmlinux)
  DEVICE_VENDOR := Zyxel
  DEVICE_MODEL := VMG8623-T50B
  DEVICE_ALT0_VENDOR := Zyxel
  DEVICE_ALT0_MODEL := EMG5523-T50B
  DEVICE_ALT1_VENDOR := Zyxel
  DEVICE_ALT1_MODEL := EMG3525-T50B

  DEVICE_PACKAGES += hostapd-mbedtls wpa-supplicant-mbedtls
endef
TARGET_DEVICES += zyxel_vmg8623-t50b