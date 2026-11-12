SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check vendor lock patch kernel m1n1 gsi check-gsi boot-image boot prep disk netboot clean

help:
	@printf '%s\n' \
	  'iDroid targets:' \
	  '  check        verify host dependencies' \
	  '  vendor       sync vendored submodules and apply patches' \
	  '  lock         regenerate vendor/versions.lock' \
	  '  patch        re-apply tracked patches only' \
	  '  kernel       build Image.gz + t8010-d101.dtb (16K pages)' \
	  '  m1n1         download prebuilt m1n1-idevice + monitor-stub' \
	  '  gsi          download + verify + extract the pinned GSI' \
	  '  check-gsi    verify the GSI is 16 KiB compatible' \
	  '  boot-image   assemble out/boot/m1n1-linux.macho' \
	  '  disk         create out/disk.img (GPT: vbmeta/system/vendor/userdata)' \
	  '  prep         prepare iBSS/DeviceTree for iPhone9,3 (root, DFU)' \
	  '  boot         boot the phone (root, DFU)' \
	  '  netboot      print netboot host instructions' \
	  '  clean        remove out/ and cache/m1n1' \
	  '' \
	  'Run scripts/check-host.sh first.'

check:
	scripts/check-host.sh

vendor:
	scripts/vendor-sync.sh

lock:
	scripts/versions-lock.sh

patch:
	scripts/apply-patches.sh

kernel:
	scripts/build-kernel.sh

m1n1:
	scripts/fetch-m1n1.sh

gsi:
	scripts/fetch-gsi.sh

check-gsi:
	scripts/check-gsi-16k.sh

boot-image:
	scripts/build-m1n1-blob.sh

disk:
	scripts/netboot/make-disk.sh

prep:
	sudo vendor/remote_boot/remoteboot.sh prep

boot:
	scripts/boot.sh

netboot:
	@printf '%s\n' \
	  '1. scripts/netboot/setup-usbnet.sh usb0' \
	  '2. scripts/netboot/serve-nbd.sh out/disk.img' \
	  '3. boot the phone with scripts/boot.sh'

clean:
	rm -rf out cache/m1n1
