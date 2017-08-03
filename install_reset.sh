#!/usr/bin/env bash

set -ex

readonly PROGNAME=$(basename $0)
readonly DEST="/mnt"
readonly DEVICE=$1
readonly GROUP=$2

check_usage() {
	if [ -z "$1" ] || [ -z "$2" ]; then
		echo "usage: $PROGNAME <DEVICE> <GROUP>"
		exit 1
	fi
}

remove() {
	umount -R $DEST || true
	lvremove -f /dev/mapper/${GROUP}-root || true
	lvremove -f /dev/mapper/${GROUP}-swap || true
	lvremove -f /dev/mapper/${GROUP}-home || true
	vgremove -f ${GROUP} || true
	pvremove -f /dev/mapper/base || true
	cryptsetup remove /dev/mapper/base || true
}

main() {
	check_usage
	remove
}

main
