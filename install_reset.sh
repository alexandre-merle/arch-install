#!/usr/bin/env bash

set -ex

dest='/mnt'
device=$1
group=$2

if [ -z "$1" ] || [ -z "$2" ]; then
	echo "usage: ${0} <device> <group>"
	exit 1
fi

umount -R $dest || true
lvremove -f /dev/mapper/${group}-root || true
lvremove -f /dev/mapper/${group}-swap || true
lvremove -f /dev/mapper/${group}-home || true
vgremove -f ${group} || true
pvremove -f /dev/mapper/base || true
cryptsetup remove /dev/mapper/base || true
