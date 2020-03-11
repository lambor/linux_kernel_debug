KRN_DIR:=/home/dcnh/MyGithub/linux
KRN_IMG:=${KRN_DIR}/arch/x86_64/boot/bzImage

BBX_DIR:=/home/dcnh/MyGithub/busybox-1.26.2
RFS_IMG:=${BBX_DIR}/rootfs.img
RFS_DIR:=_install

TEST_DIR:=/home/dcnh/MyGithub/kern_test_bin
TEST_BIN:=${TEST_DIR}/test

NETIP_PREFIX:=172.30.0
TAP0:=tap_0
BR0:=br_0

TMP_DIR:=${shell mktemp -d}

${TEST_BIN}: ${TEST_DIR}/Makefile
	make -C ${TEST_DIR}

${RFS_IMG}: ${TEST_BIN}
	make -C ${BBX_DIR} defconfig
	cd ${BBX_DIR}; sed -i -e '/CONFIG_PREFIX=/d' -e '/CONFIG_STATIC=/d' -e '$$ a CONFIG_PREFIX="./${RFS_DIR}"' -e '$$ a CONFIG_STATIC=y' ${BBX_DIR}/.config
	make -C ${BBX_DIR} install
	cd ${BBX_DIR}/${RFS_DIR}; mkdir -p proc sys dev etc etc/init.d mnt lib/modules/5.1.0-rc5+
	printf "#!/bin/sh\nmount -t proc none /proc\nmount -t sysfs none /sys\n/sbin/mdev -s" > ${BBX_DIR}/${RFS_DIR}/etc/init.d/rcS
	printf "#!/bin/sh\nip addr add ${NETIP_PREFIX}.10/24 dev \$$1;\nip link set \$$1 up;\nip route add default via ${NETIP_PREFIX}.1 dev \$$1" > ${BBX_DIR}/${RFS_DIR}/setup_static_net.sh 
	printf "#!/bin/sh\nip link set \$$1 up;\nudhcpc -i \$$1 -s /etc/udhcp/simple.script" > ${BBX_DIR}/${RFS_DIR}/setup_dhcp_net.sh
	printf "#!/bin/sh\nmount -t cifs //10.0.2.4/qemu /mnt -o username=guest" > ${BBX_DIR}/${RFS_DIR}/mount_smb.sh
	chmod +x ${BBX_DIR}/${RFS_DIR}/etc/init.d/rcS
	chmod +x ${BBX_DIR}/${RFS_DIR}/*.sh
	# chmod +x ${BBX_DIR}/${RFS_DIR}/setup_dhcp_net.sh
	cp ${TEST_BIN} ${BBX_DIR}/${RFS_DIR}/hello
	cp -r ${BBX_DIR}/examples/udhcp ${BBX_DIR}/${RFS_DIR}/etc
	cp ${BBX_DIR}/external_bin/* ${BBX_DIR}/${RFS_DIR}/bin
	cd ${BBX_DIR}/${RFS_DIR}; find . | cpio -o --format=newc > /$@

${KRN_IMG}:
	make -C ${KRN_DIR} mrproper
	make -C ${KRN_DIR} x86_64_defconfig
	printf "CONFIG_DEBUG_INFO=y\nCONFIG_DEBUG_KERNEL=y\nCONFIG_GDB_SCRIPTS=y\nCONFIG_CIFS=y" > "${TMP_DIR}/.config-fragment"
	cd ${KRN_DIR} && scripts/kconfig/merge_config.sh .config "${TMP_DIR}/.config-fragment"
	make -C ${KRN_DIR} -j$$((($$(nproc)+1)/2))

boot: ${KRN_IMG} ${RFS_IMG} ${TAP0}
	qemu-system-x86_64 \
		-smp 8 -numa node,nodeid=0 -numa node,nodeid=1 \
		-nographic \
		-smp 4 \
		-kernel ${KRN_IMG} \
		-initrd ${RFS_IMG} \
		-append 'root=/dev/ram rdinit=/sbin/init console=ttyS0 nokaslr loglevel=8' \
		-S -s \
		-netdev tap,id=mynet0,ifname=${TAP0},script=no,downscript=no -device e1000,netdev=mynet0 \
		-usb \
		-net nic -net user,smb=${PWD}/./ldd

${BR0}:
	ip link | grep $@ > /dev/null || { sudo ip link add $@ type bridge; sudo ip addr add ${NETIP_PREFIX}.1/24 dev $@; }

${TAP0}: ${BR0}
	ip link | grep $@ > /dev/null || { sudo ip tuntap add $@ mode tap; sudo ip link set $@ master $<; }
	sudo ip link set $< up
	sudo ip link set $@ up

gdb:
	cd ${KRN_DIR} && gdb -ex "add-auto-load-safe-path ." \
		-ex "file vmlinux" \
		-ex "target remote localhost:1234"

clean_bzImage:
	rm -f ${KRN_IMG}

clean_rootfs:
	rm -f ${RFS_IMG}

clean_net:
	ip link | grep ${TAP0} > /dev/null && sudo ip link del ${TAP0}
	ip link | grep ${BR0} > /dev/null && sudo ip link del ${BR0}

.PHONY: ${BR0} ${TAP0} boot gdb clean_bzImage clean_rootfs clean_net
