#!/bin/bash
# Phoenix-RTOS
#
# Operating system kernel
#
# Creates syspage for i.MX RT based on given apps.
#
# Copyright 2017-2019 Phoenix Systems
# Author: Aleksander Kaminski
#
# This file is part of Phoenix-RTOS.

# This script creates image of Phoenix-RTOS kernel, syspage and aplications for i.MX RT platform.
# Created image can be programmed directly to the device.
# Usage:
# $1      - path to Phoenix-RTOS kernel ELF
# $2      - output file name
# $3, ... - applications ELF(s)
# example: ./mkimg-imxrt.sh phoenix-armv7-imxrt.elf flash.img app1.elf app2.elf


reverse() {
	num=$1
	printf "0x"
	for i in 1 2 3 4; do
		printf "%02x" $(($num & 0xff))
		num=$(($num>>8))
	done
}


if [ -z "$CROSS" ]
then
	CROSS="arm-phoenix-"
fi


KERNELELF=$1
shift

OUTPUT=$1
shift

GDB_SYM_FILE=`dirname ${OUTPUT}`"/gdb_symbols"

SIZE_PAGE=$((0x200))
PAGE_MASK=$((0xfffffe00))
KERNEL_END=$((`readelf -l $KERNELELF | grep "LOAD" | grep "R E" | awk '{ print $6 }'`))
FLASH_START=$((0x08000000))
APP_START=$((0x08010000))
SYSPAGE_START=$((0x08000200))

declare -i i
declare -i j

i=$((0))


if [ $KERNEL_END -gt $(($APP_START-$FLASH_START)) ]; then
	echo "Kernel image is bigger than expected!"
	printf "Kernel end: 0x%08x > App start: 0x%08x\n" $KERNEL_END $APP_START
	exit 1
fi

rm -f *.img
rm -f syspage.hex syspage.bin
rm -f $OUTPUT

prognum=$((`echo $@ | wc -w`))

printf "%08x%08x" $((`reverse 0x20000000`)) $((`reverse 0x20040000`)) >> syspage.hex
printf "%08x%08x" 0 $((`reverse $prognum`)) >> syspage.hex
i=16

OFFSET=$(($APP_START))

for app in $@; do
	echo "Proccessing $app"

	printf "%08x" $((`reverse $OFFSET`)) >> syspage.hex #start

	cp $app tmp.elf
	${CROSS}strip tmp.elf
	SIZE=$((`du -b tmp.elf | cut -f1`))
	rm -f tmp.elf
	END=$(($OFFSET+$SIZE))
	printf "%08x" $((`reverse $END`)) >> syspage.hex #end
	i=$i+8

	OFFSET=$((($OFFSET+$SIZE+$SIZE_PAGE-1)&$PAGE_MASK))

	j=0
	for char in `basename "$app" | sed -e 's/\(.\)/\1\n/g'`; do
		printf "%02x" "'$char" >> syspage.hex
		j=$j+1
	done

	for (( ; j<16; j++ )); do
		printf "%02x" 0 >> syspage.hex
	done

	i=$i+16
done

# Use hex file to create binary file
xxd -r -p syspage.hex > syspage.bin

# Make kernel binary image
${CROSS}objcopy $KERNELELF -O binary kernel.img

cp kernel.img $OUTPUT

OFFSET=$(($SYSPAGE_START-$FLASH_START))
dd if="syspage.bin" of=$OUTPUT bs=1 seek=$OFFSET conv=notrunc 2>/dev/null

[ -f $GDB_SYM_FILE ] && rm -rf $GDB_SYM_FILE
printf "file %s \n" `realpath $KERNELELF` >> $GDB_SYM_FILE

OFFSET=$(($APP_START-$FLASH_START))
for app in $@; do
	cp $app tmp.elf
	${CROSS}strip tmp.elf
	printf "App %s @offset 0x%08x\n" $app $OFFSET
	printf "add-symbol-file %s 0x%08x\n" `realpath $app` $((OFFSET + $FLASH_START + $((0xc0)))) >> $GDB_SYM_FILE
	dd if=tmp.elf of=$OUTPUT bs=1 seek=$OFFSET 2>/dev/null
	OFFSET=$((($OFFSET+$((`du -b tmp.elf | cut -f1`))+$SIZE_PAGE-1)&$PAGE_MASK))
	rm -f tmp.elf
done

#Convert binary image to hex
${CROSS}objcopy --change-addresses $FLASH_START -I binary -O ihex ${OUTPUT} ${OUTPUT%.*}.hex

rm -f kernel.img
rm -f syspage.bin
rm -f syspage.hex

echo "Image file `basename ${OUTPUT}` has been created"