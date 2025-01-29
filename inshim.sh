#!/bin/bash

[ "$EUID" -ne 0 ] && fail "Not running as root, this shouldn't happen! Failing."

fail() {
	printf "%b\n" "$*" >&2 || :
	sleep 1d
}

get_largest_cros_blockdev() {
	local largest size dev_name tmp_size remo
	size=0
	for blockdev in /sys/block/*; do
		dev_name="${blockdev##*/}"
		echo -e "$dev_name" | grep -q '^\(loop\|ram\)' && continue
		tmp_size=$(cat "$blockdev"/size)
		remo=$(cat "$blockdev"/removable)
		if [ "$tmp_size" -gt "$size" ] && [ "${remo:-0}" -eq 0 ]; then
			case "$(sfdisk -d "/dev/$dev_name" 2>/dev/null)" in
				*'name="STATE"'*'name="KERN-A"'*'name="ROOT-A"'*)
					largest="/dev/$dev_name"
					size="$tmp_size"
					;;
			esac
		fi
	done
	echo -e "$largest"
}

format_part_number() {
	echo -n "$1"
	echo "$1" | grep -q '[0-9]$' && echo -n p
	echo "$2"
}

verified() {
	rm /tmp/.developer_mode 2> /dev/null
	crossystem disable_dev_request=1 || fail "Failed to set disable_dev_request."
}

mount /dev/disk/by-label/STATE /mnt/stateful_partition/
cros_dev="$(get_largest_cros_blockdev)"
if [ -z "$cros_dev" ]; then
    echo "No CrOS SSD found on device. Failing."
    sleep 1d
fi
stateful=$(format_part_number "$cros_dev" 1)
mkfs.ext4 -F "$stateful" || fail "Failed to wipe stateful." # This only wipes the stateful partition 
mount "$stateful" /tmp || fail "Failed to mount stateful."
mkdir -p /tmp/unencrypted
cp /mnt/stateful_partition/usr/share/packeddata/. /tmp/unencrypted/ -rvf
chown 1000 /tmp/unencrypted/PKIMetadata -R
echo -e "Is this your first time doing icarus for this particular instance? (Y/n)"
read -p "> " -n1 skidproof_firstcheck # Makes sure the skids understand that they should not enable developer mode on the first attempt; hopefully will limit pings for help
printf "\n"
case $skidproof_firstcheck in  
  y|Y) verified ;;
  n|N) echo "Return to verified? (y/N)"
       read -p "> " -n1 dev
       case $dev in  
         y|Y) verified ;; 
         n|N) touch /tmp/.developer_mode 
		echo -e "\n\n\033[33mNOTE: You still need to connect to the server on this run as well. \033[0m\n" ;;
         *) touch /tmp/.developer_mode 
		echo -e "\n\n\033[33mNOTE: You still need to connect to the server on this run as well. \033[0m\n" ;;
       esac ;;
  *) verified ;; 
esac
umount /tmp
read -p "Finished! Press enter to reboot."
reboot
