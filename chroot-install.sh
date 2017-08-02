#!/usr/bin/env bash

device=$1
group=$2

mkdir /run/lvm
mount --bind /hostrun/lvm /run/lvm

# setting timezone
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# setting en_US locale
sed -i s/#en_US.UTF-8/en_US.UTF-8/g /etc/locale.gen
# generating locales
locale-gen

# setting hostname
echo "${group}-computer" > /etc/hostname

# adding hostname to hosts
cat >> /etc/hosts <<EOF
127.0.1.1	${group}-computer.localdomain ${group}-computer
EOF

# setting root password
passwd

pacman -Sy --noconfirm grub efibootmgr

# configuration of grub for encryption on top of lvm / volume
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=${device}3:base\"" >> /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub

# add hooks to mkinitcpio
echo "HOOKS=\"base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck\"" >> /etc/mkinitcpio.conf

mkinitcpio -p linux

grub-mkconfig -o /boot/grub/grub.cfg
mkdir -p /boot/efi/EFI
grub-install --recheck --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch_grub

umount /run/lvm

# leaving chroot env
exit
