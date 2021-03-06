#!/usr/bin/env bash

set -ex

readonly DEVICE=$1
readonly GROUP=$2
readonly USER=$3

lvm_mount() {
  mkdir /run/lvm
  mount --bind /hostrun/lvm /run/lvm
}

set_locales() {
  # setting timezone
  ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
  hwclock --systohc

  # setting en_US locale
  sed -i "s/#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen
  # generating locales
  locale-gen

  # setting hostname
  echo "${GROUP}-computer" > /etc/hostname

  # adding hostname to hosts
  echo "127.0.1.1	${GROUP}-computer.localdomain ${GROUP}-computer" >> /etc/hosts
}

root_install() {
  # setting root password
  passwd

  pacman -Sy --noconfirm grub efibootmgr sudo
}

boot_install() {
  local root_disk=$(find -L /dev/disk/by-uuid -samefile ${DEVICE}3)
  # configuration of grub for encryption on top of lvm / volume
  echo "GRUB_CMDLINE_LINUX=\"cryptdevice=${root_disk}:base\"" >> /etc/default/grub
  echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub

  # add hooks to mkinitcpio
  echo "HOOKS=\"base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck\"" >> /etc/mkinitcpio.conf

  mkinitcpio -p linux

  grub-mkconfig -o /boot/grub/grub.cfg
  mkdir -p /boot/efi/EFI
  grub-install --recheck --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch_grub
}

internet_setup() {
  local iethernet=$(ip addr | grep '[0-9]: en' | cut -d ':' -f 2 | tr -d ' ')

  for interface in $iethernet; do
    systemctl enable dhcpcd@$interface
  done
}

user_install() {
  useradd -m -g users -G adm,log,wheel -s /bin/bash $USER
  echo '%wheel      ALL=(ALL) ALL' | EDITOR='tee -a' visudo
  passwd $USER
}

gui_install() {
  pacman -Sy --noconfirm nvidia nvidia-utils lightdm-gtk-greeter xorg-server xorg-xinit xterm xorg-xclock awesome
  systemctl enable lightdm.service
}

finish() {
  umount /run/lvm

  internet_setup
  gui_install
  # leaving chroot env
  exit
}

main() {
  lvm_mount
  set_locales
  root_install
  user_install
  boot_install
  finish
}

main
