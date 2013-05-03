#!/bin/bash -e
#
# Copyright (c) 2013 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

if ! id | grep -q root; then
	echo "must be run as root"
	exit
fi

DISK=/dev/mmcblk1

network_down () {
	echo "Network Down"
	exit
}

ping -c1 www.google.com | grep ttl >/dev/null 2>&1 || network_down

check_host_pkgs () {
	unset deb_pkgs
	dpkg -l | grep dosfstools >/dev/null || deb_pkgs="${deb_pkgs}dosfstools "
	dpkg -l | grep parted >/dev/null || deb_pkgs="${deb_pkgs}parted "
	dpkg -l | grep rsync >/dev/null || deb_pkgs="${deb_pkgs}rsync "

	if [ "${deb_pkgs}" ] ; then
		echo "Installing: ${deb_pkgs}"
		apt-get update -o Acquire::Pdiffs=false
		apt-get -y install ${deb_pkgs}
	fi
}

format_boot () {
	fdisk ${DISK} <<-__EOF__
	a
	1
	w
	__EOF__
	sync

	mkfs.vfat -F 16 ${DISK}p1 -n boot
	sync
}

format_root () {
	mkfs.ext4 ${DISK}p2 -L rootfs
	sync
}

repartition_emmc () {
	dd if=/dev/zero of=${DISK} bs=1024 count=1024
	parted --script ${DISK} mklabel msdos
	sync

	fdisk ${DISK} <<-__EOF__
	n
	p
	1
	 
	+64M
	t
	e
	p
	w
	__EOF__
	sync

	format_boot

	fdisk ${DISK} <<-__EOF__
	n
	p
	2
	 
	 
	w
	__EOF__
	sync

	format_root
}

mount_n_check () {
	umount ${DISK}p1 || true
	umount ${DISK}p2 || true

	lsblk | grep mmcblk1p1 >/dev/null 2<&1 || repartition_emmc
	mkdir -p /tmp/boot/ || true
	if mount -t vfat ${DISK}p1 /tmp/boot/ ; then
		if [ -f /tmp/boot/MLO ] ; then
			umount ${DISK}p1 || true
			format_boot
			format_root
		else
			umount ${DISK}p1 || true
			repartition_emmc
		fi
	else
		repartition_emmc
	fi
}

copy_boot () {
	mkdir -p /tmp/boot/ || true
	mount ${DISK}p1 /tmp/boot/
	#Make sure the BootLoader gets copied first:
	cp -v /boot/uboot/MLO /tmp/boot/MLO
	cp -v /boot/uboot/u-boot.img /tmp/boot/u-boot.img

	rsync -aAXv /boot/uboot/ /tmp/boot/ --exclude={MLO,u-boot.img,*bak}
	sync
	umount ${DISK}p1 || true
}

copy_rootfs () {
	mkdir -p /tmp/rootfs/ || true
	mount ${DISK}p2 /tmp/rootfs/
	rsync -aAXv /* /tmp/rootfs/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found,/boot/*,/lib/modules/*}
	mkdir -p /tmp/rootfs/boot/uboot/ || true
	mkdir -p /tmp/rootfs/lib/modules/`uname -r` || true
	rsync -aAXv /lib/modules/`uname -r`/* /tmp/rootfs/lib/modules/`uname -r`/
	sync
	umount ${DISK}p2 || true
	echo ""
	echo "This script has now completed it's task"
	echo "-----------------------------"
	echo "Note: Actually reset the board, a software reset [sudo reboot] is not enough."
	echo "-----------------------------"
}

check_host_pkgs
mount_n_check
copy_boot
copy_rootfs
