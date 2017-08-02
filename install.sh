#!/usr/bin/env bash

set -ex

ping -c 1 www.google.com
dest='/mnt'
device=$1
group=$2
reset=false
if [ ! -z "$3" ]; then
	reset=true
fi

if [ -z "$1" ] || [ -z "$2" ]; then
	echo "usage: ${0} <device> <group>"
	exit 1
fi

if [ reset ]; then
	curl -O https://raw.githubusercontent.com/alexandre-merle/arch-install/master/install_reset.sh && bash install_reset.sh $1 $2
fi

# destroying mbr or gpt
sgdisk -Z $device
# creating new gpt table
sgdisk -og $device
# refresh os table partition information
partprobe $device
# setup partitions
sgdisk -n 1:2048:1026047 -c 1:"EFI System Partition" -t 1:ef00 $device
sgdisk -n 2:1026048:3074047 -c 2:"Linux /boot" -t 2:8300 $device
# get end of disk
end_sector=`sgdisk -E ${device}`
sgdisk -n 3:3074048:${end_sector} -c 3:"Linux LVM" -t 3:8e00 $device
# print partition table
sgdisk -p ${device}

# setup encryption
cryptsetup luksFormat -c aes-xts-plain64 -s 512 ${device}3
cryptsetup open ${device}3 base

# initializing LVM volume
pvcreate -f /dev/mapper/base
# creating volume group
vgcreate ${group} /dev/mapper/base
# creating LVM partitions
lvcreate -L 50G -n root ${group}
lvcreate -L 2G -C y -n swap ${group}
lvcreate -l 100%FREE -n home ${group}

# creating filesystem for partitions
mkfs.ext4 -L archsystem /dev/mapper/${group}-root
mkfs.ext4 -L archuser /dev/mapper/${group}-home
mkswap /dev/mapper/${group}-swap
boot_disk=`find -L /dev/disk/by-path -samefile ${device}2`
efi_boot_disk=`find -L /dev/disk/by-path -samefile ${device}1`
mkfs.ext4 -L boot ${boot_disk}
mkfs.fat -F32 ${efi_boot_disk}

# mouting volumes
mkdir -p ${dest}
mount /dev/mapper/${group}-root ${dest}
mkdir -p ${dest}/boot
mount ${boot_disk} ${dest}/boot
mkdir -p ${dest}/boot/efi
mount ${efi_boot_disk} ${dest}/boot/efi
mkdir -p ${dest}/home
mount /dev/mapper/${group}-home ${dest}/home

# installing basic system
pacstrap ${dest} base

# generating fstab
genfstab -U -p ${dest} >> ${dest}/etc/fstab

# adding swap to fstab
echo "/dev/mapper/${group}-swap swap swap defaults 0 0" >> ${dest}/etc/fstab

# getting chroot installation script
(cd $dest/root && curl -O https://raw.githubusercontent.com/alexandre-merle/arch-install/master/chroot-install.sh)

mkdir ${dest}/hostrun
mount --bind /run ${dest}/hostrun

# chroot to the new system and run installation script
arch-chroot $dest /bin/bash /root/chroot-install.sh ${device} ${group}

umount ${dest}/hostrun

# umount all partitions
umount -R ${dest}
