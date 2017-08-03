#!/usr/bin/env bash

set -ex

readonly PROGNAME=$(basename $0)
readonly DEST="/mnt"
readonly DEVICE=$1
readonly GROUP=$2

test_connection() {
  ping -c 1 www.google.com
}

check_args() {
  if [ -z $DEVICE ] || [ -z $GROUP ]; then
	  echo "usage: ./$PROGNAME <DEVICE> <GROUP>"
	  exit 1
  fi

  if [ -z "$3" ]; then
	  curl -O https://raw.githubusercontent.com/alexandre-merle/arch-install/master/install_reset.sh && bash install_reset.sh $DEVICE $GROUP
  fi
}

partition_disk() {
	# DESTroying mbr or gpt
	sgdisk -Z $DEVICE
	# creating new gpt table
	sgdisk -og $DEVICE
	# refresh os table partition information
	partprobe $DEVICE
	# setup partitions
	sgdisk -n 1:2048:1026047 -c 1:"EFI System Partition" -t 1:ef00 $DEVICE
	sgdisk -n 2:1026048:3074047 -c 2:"Linux /boot" -t 2:8300 $DEVICE
	# get end of disk
	local end_sector=$(sgdisk -E $DEVICE)
	sgdisk -n 3:3074048:${end_sector} -c 3:"Linux LVM" -t 3:8e00 $DEVICE
	# print partition table
	sgdisk -p ${DEVICE}
}

format_disk() {
	# setup encryption
	cryptsetup luksFormat -c aes-xts-plain64 -s 512 ${DEVICE}3
	cryptsetup open ${DEVICE}3 base

	# initializing LVM volume
	pvcreate -f /dev/mapper/base
	# creating volume GROUP
	vgcreate ${GROUP} /dev/mapper/base
	# creating LVM partitions
	lvcreate -L 50G -n root ${GROUP}
	lvcreate -L 2G -C y -n swap ${GROUP}
	lvcreate -l 100%FREE -n home ${GROUP}

	# creating filesystem for partitions
	mkfs.ext4 -L archsystem /dev/mapper/${GROUP}-root
	mkfs.ext4 -L archuser /dev/mapper/${GROUP}-home
	mkswap /dev/mapper/${GROUP}-swap
	local boot_disk=$(find -L /dev/disk/by-path -samefile ${DEVICE}2)
	local efi_boot_disk=$(find -L /dev/disk/by-path -samefile ${DEVICE}1)
	mkfs.ext4 -L boot ${boot_disk}
	mkfs.fat -F32 ${efi_boot_disk}
}

mount_volumes() {
	# mouting volumes
	local boot_disk=$(find -L /dev/disk/by-path -samefile ${DEVICE}2)
	local efi_boot_disk=$(find -L /dev/disk/by-path -samefile ${DEVICE}1)
	mkdir -p ${DEST}
	mount /dev/mapper/${GROUP}-root ${DEST}
	mkdir -p ${DEST}/boot
	mount ${boot_disk} ${DEST}/boot
	mkdir -p ${DEST}/boot/efi
	mount ${efi_boot_disk} ${DEST}/boot/efi
	mkdir -p ${DEST}/home
	mount /dev/mapper/${GROUP}-home ${DEST}/home
}

install_basic() {
	# installing basic system
	pacstrap ${DEST} base

	# generating fstab
	genfstab -U -p ${DEST} >> ${DEST}/etc/fstab

	# adding swap to fstab
	echo "/dev/mapper/${GROUP}-swap swap swap defaults 0 0" >> ${DEST}/etc/fstab

	# getting chroot installation script
	(cd $DEST/root && curl -O https://raw.githubusercontent.com/alexandre-merle/arch-install/master/chroot-install.sh)
}

lvm_init() {
	mkdir ${DEST}/hostrun
	mount --bind /run ${DEST}/hostrun
}

launch_chroot() {
	# chroot to the new system and run installation script
	arch-chroot $DEST /bin/bash /root/chroot-install.sh ${DEVICE} ${GROUP}
}

unmount() {
	umount ${DEST}/hostrun

	# umount all partitions
	umount -R ${DEST}
	echo "Installation finished"
}

main() {
	test_connection
	check_args
	partition_disk
	format_disk
	mount_volumes
	install_basic
	lvm_init
	launch_chroot
	unmount
}

main
