# diskdive
visual summary of disks and partitions in terminal

* creates bar graphs for each drive showing relative partition sizes within
* each partition in it's own colour
* key for partition names at bottom (unique according to partition size+name)


# requirements
* lsblk
* smartctl (from smartmontools in debian)
* parted 
* common shell utilities (bc, awk, sort, uniq, grep, sed, tr...)
* must be run as root


# Bugs
* should be smarter about identifying required utilities
* only tested against fairly normal GPT/MBR on x86 arch hardware/kvm with debian and ubuntu

# TODO
* improve barchart structure - 
  * where small partitions round up to 1 char long, the space is "stolen" from the next partition. It should instead be stolen from the largest partition!
* improve performance (minimise external calls?)
* improve performance (port to python?)
* widen functionality to do similar for:
  * mdadm software raid layer
  * lvm layers
  * crypt layer?
  * filesystem layer (df, basically?)
