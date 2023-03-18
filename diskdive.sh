#!/bin/bash
# set -x

# create bar graphs for each drive showing relative partition size
# all at scame scale, regardless of different drive sizes (ie, scale largest size to terminal width, and all others to match same scaling factor)
# each partition in it's own colour
# key for partition names at bottom
# loop in info from proc/partitions ?
# partition sizes can be got from /proc/partitions, but
# gdisk gives start/end values which ensure order and position are correct
# 6TB drive means each chart is about 70G. Round partitions up to 1char min. 
# calculate partition character scale from smallest partition first
# partition colour sequence according to predefined chart of some kind, ensuring that same partition NAME gets the same colour, regardless of order within drive

# all disk sizes are in KiB (originally to match /proc/partitions)
# device major 8 = SCSI disk devices
# 259 is "block extended major" for dynamic. I've found it to be used for nvme
#  https://www.kernel.org/doc/Documentation/admin-guide/devices.txt
# bigd=$(lsblk -n -I 8,259 -d -b -o SIZE  | sort -g | tail -1)

# prerequisites
# * lsblk
# * smartctl
# * parted
# * common shell utilities (bc, awk, sort, uniq, grep, sed, tr...)

# TODO
# * improve barchart structure - 
#	where small partitions round up to 1 char long, 
#	the space is "stolen" from the next partition. 
#	It should instead be stolen from the largest partition!
# * improve performance (minimise external calls?)
# * improve performance (port to python?)
# * widen functionality to do similar for:
#       * mdadm software raid layer
#       * lvm layers
#       * crypt layer?
#       * filesystem layer (df, basically?)

# BUGS/ISSUES
# * only tested against fairly normal GPT/MBR on x86 arch so far

reset=$(tput sgr0)
origIFS=$IFS
# TODO: provide arrays for larger values (>16) of `tput colors` 
declare -a colarray
declare -a colcount
colarray=(14 9 10 11 13 12 7 6 1 2 3 5 4 15 14 9 10 11 13 12 7 6 1 2 3 5 4 15)
colindex=0

do_findparts() {
    # partitions we care about. If GPT, then it's just what's on disk. 
    # But if we're msdos/MBR, then we only care about primary and logical (not extended)
    # type "loop" may be seen on XEN VMs and can be treated same as GPT

    type=$(parted /dev/$dsk print | awk '/Partition Table:/ {print $3}' )

    case $type in
        gpt|loop)
            parted -m /dev/$dsk unit KiB print | grep "^[0-9]" 
            ;;
        msdos)
            join -t: <(parted /dev/$dsk print | grep -e "^ .*\(primary\|logical\)" | awk '{print $1}')  <(parted -m /dev/$dsk unit KiB print | grep "^[0-9]")
            ;;
        *)
            echo "Unrecognised partition type $type" >/dev/stderr
    esac

}

bigd=$(lsblk -n -b -d -o SIZE,NAME,TYPE | awk '/disk/ {print $1}' | sort -g | tail -1)
bigd=$((bigd/1024))	# size in KiB

columns=$(tput cols)
rawbar="$(printf %${columns}s ".")"

# header output
echo "  $(date -R)  -  Scale: maximum $(echo "scale=1;$bigd/$columns/1024/1024" | bc) GiB per character"
echo ""

for dsk in $(lsblk -n -b -d -o NAME,TYPE | awk '/disk/ {print $1}') ; do
    echo -n $reset

    # disk info
    smartinfo=$(smartctl -i /dev/${dsk})

    model="$(echo "$smartinfo" | awk '/Model/ {$1=$2=""; print $0}' | tail -1 | tr -s " ")"
    dsize=$(grep ${dsk##*/}$ /proc/partitions | awk '{print $3}')
    dsizebin=$((dsize/1024/1024))			# binary GiB
    dsizedec=$(echo "scale=0;$dsize*1024/1000000000"| bc) # decimal GB
    suf=GB
    [ $dsizedec -ge 1024 ] && dsizedec=$(echo "scale=1;$dsize*1024/1000000000000"| bc) && suf=TB # decimal TB

    smartdata=$(smartctl -A /dev/$dsk)

    rpm=$(echo "$smartinfo" | awk '/Rate:/ {print $3}')
    case $rpm in
        [0-9]*) rpm=" [${rpm} RPM]"  ;;
        Solid)  rpm=" [SSD]"        ;;
    esac

    ageh=$(echo "$smartdata" | grep Power.On.Hours | sed -e 's/(.*)//g' | awk '{print $NF}' | tr -d ,)
    if [ -n "$ageh" ] ; then
        aged="$(echo "scale=1;$ageh/24" | bc)"
        age=" [$aged days]"
        alldiskages="$alldiskages
${aged%.*} $dsk"
    else
        age=""
    fi

    temp=$(echo "$smartdata" | grep ^194 | sed -e 's/(.*)//g' | awk '{print $NF}')
    [ -z "$temp" ] && temp=$(echo "$smartdata" | awk '/Temperature:/ {print $2}')
    if [ -n "$temp" ] ; then
        temp=" [${temp}°C]"
    else
        temp=""
    fi

    echo "${dsk##*/} ${dsizebin}GiB (${dsizedec}${suf})${model}${rpm}${age}${temp}"

    # now give us partition info too
    barfill=0	# each disk starts with total bar empty
    IFS=: ; while read pnum start end psize fs name flags ; do
        echo -n $reset
        start=${start%k*}
        end=${end%k*}
        psize=${psize%k*}
    	psizehum=$(echo "scale=1;$psize/1024" | bc)      ; suf=MiB 
	[ ${psizehum%.*} -ge 1024 ] && psizehum=$(echo "scale=1;$psize/1024/1024" | bc) && suf=GiB 
        [ ${psizehum%.*} -ge 1024 ] && psizehum=$(echo "scale=2;$psize/1024/1024/1024"| bc) && suf=TiB
	
	# printf to get rounding how I want it
	endsegment=$(printf "%.f" $(echo "scale=10;$end*$columns/$bigd" | bc))
	barsegment=$((endsegment-barfill))
	[ $barsegment -lt 1 ] && barsegment=1 && endsegment=$((barfill+1))
	barfill=$endsegment

	pseen=$(echo -e "$key" | grep " $name ($psizehum $suf)" | awk '{print $1}')
	# echo "$key"
	if [ -n "$pseen" ] ; then
		# this partition type seen before. We should count it up somehow
		colcount[$pseen]=$((${colcount[$pseen]}+1))
		bgcol=${colarray[$pseen]}

	else
		# this partition type is new. Assign it a colour
		colcount[$colindex]=$((${colcount[$colindex]}+1))
		bgcol=${colarray[$colindex]}
		key="$key ${colindex} $(tput setab $bgcol)    ${reset} ${name} ($psizehum $suf) \n"
		colindex=$((colindex+1)) # prepare for the next
	fi

	tput setab $bgcol
	tput setaf black
	outbar=$pnum$rawbar
	echo -n "${outbar:0:$barsegment}"
#        echo $pnum __ $start __ $end __ $size __ $fs __ $name __ $flags
    done < <(do_findparts)
    echo "$reset"
#    echo "" ### line between disk entries
done

echo ""	### line before key

# reset colours and IFS
echo -n $reset
IFS=$origIFS

# echo "$key"

# let's have a bar graph of disk ages
alldiskages="$(echo "$alldiskages" | grep "sd[a-f]" | sort -g)"   # filter to disks we care about
diskcount=$(echo "$alldiskages" | wc -l)
ideallength=$(($columns/$diskcount))
agecolumns=$(($ideallength*$diskcount))
oldestdisk=$(echo "$alldiskages" | sort -g | cut -d" " -f 1 | tail -1)

rulerdays=900
rulercols=$(($columns-2))

# show a "ruler" of age against which disks are positioned
#
# this is a "standard" ruler of 900 days, scaled to columns-2, with markings
# equal to the number of disks. The scale ends at the columns-2 and the final
# two characters are reserved for 100-133.3333% age "warning" column for "due
# for change", and over that is "critical" = overdue change. 
#
# 900days ~= 2.5 years,  133% of 900 days = 1200 days ~= 3.28 years
# ...that's a 300 day window of aging to change disks. That ~3years/disk policy
# with some wiggle room to allow re-spacing of disks

echo "AgeRuler: ${rulerdays}d ($(echo "scale=1;$rulerdays/$rulercols" | bc)d/char - $(echo "scale=1;$rulerdays/$diskcount" | bc)d/segment) [replace at 1000-1100 (±100) days]"
oldlocation=0
# echo "123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 "
# create the rule, with $diskcount number of segments
for dnum in $(seq 1 $diskcount) ; do
    location=$(($dnum*$rulercols/$diskcount))
    width=$((location-oldlocation))
    tput setab $((dnum%2+4))
    printf "%${width}s" "|"
    oldlocation=$location
done
tput sgr0
echo "$alldiskages" | while read diskage disk ; do
    # check if our disk age overflows the ruler
    if [ $diskage -gt $rulerdays ] ; then
        # check if it overflows a LOT
        if [ $diskage -gt $((rulerdays*1333/1000)) ] ; then
            barlimit=$((rulercols+2))
            tput setaf 1 ; tput rev
        else
            barlimit=$((rulercols+1))
            tput setaf 3 ; tput rev
        fi
    else
        barlimit=$(($diskage*$rulercols/$rulerdays))
    fi
    tput cub $columns ; tput cuf $barlimit  # move to spot
    [ $barlimit -lt $columns ] && tput cub 1   # adjust spot on the ruler
    echo -n ${disk:2:1}                 # mark the spot
done
tput sgr0
echo ""
echo ""

# echo "$alldiskages"     # debug


c=0
while [ -n "${colcount[$c]}" ] ; do
	key=$(echo "$key" | sed -e "s/ $c /  ${colcount[$c]}x /g")
	c=$((c+1))
done

echo -e "$key" | column

grep "\(^md\|U\)" /proc/mdstat | tr -s " "
