SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check vendor lock patch kernel m1n1 gsi check-gsi initramfs vendor-image boot-image linux-image boot prep disk rootfs disk-linux netboot clean

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
	  '  initramfs    build the Android first-stage ramdisk' \
	  '  vendor-image build out/vendor.img (split SELinux policy)' \
	  '  boot-image   assemble out/boot/m1n1-linux.macho (Linux + first-stage ramdisk)' \
	  '  linux-image  assemble a debug bundle without the first-stage ramdisk' \
	  '  rootfs       build out/rootfs.img (Alpine aarch64) for NBD' \
	  '  disk-linux   create out/disk-linux.img (GPT: rootfs/data)' \
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

initramfs:
	scripts/build-android-initramfs.sh

vendor-image:
	scripts/build-vendor-image.sh

boot-image: initramfs
	INITRAMFS="$(CURDIR)/out/initramfs/initramfs.gz" scripts/build-m1n1-blob.sh

linux-image:
	scripts/build-m1n1-blob.sh

disk:
	SYSTEM_IMG="$(CURDIR)/cache/gsi/current/system.img" scripts/netboot/make-disk.sh

rootfs:
	scripts/build-alpine-rootfs.sh

disk-linux: rootfs
	scripts/netboot/make-linux-disk.sh

prep:
	sudo vendor/remote_boot/remoteboot.sh prep

boot:
	scripts/boot.sh

netboot:
	@printf '%s\n' \
	  '1. make rootfs                          # out/rootfs.img (Alpine aarch64)' \
	  '2. make disk-linux                      # out/disk-linux.img (GPT: rootfs/data)' \
	  '3. sudo scripts/netboot/setup-usbnet.sh usb0' \
	  '4. sudo scripts/netboot/serve-nbd.sh out/disk-linux.img' \
	  '5. make boot-image && sudo make boot   # DFU boot the phone' \
	  '' \
	  'Link addressing lives in config/netboot.conf (default 192.168.137.1 phone / .2 host).'

clean:
	rm -rf out cache/m1n1
