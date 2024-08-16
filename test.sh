#!/usr/bin/env bash

set -oue pipefail

# device names that persist across reboots
d16_a=/dev/disk/by-path/pci-0000:82:00.0-sas-phy0-lun-0
d16_b=/dev/disk/by-path/pci-0000:82:00.0-sas-phy1-lun-0
d16_c=/dev/disk/by-path/pci-0000:82:00.0-sas-phy5-lun-0
d16_d=/dev/disk/by-path/pci-0000:82:00.0-sas-phy6-lun-0
d8_a=/dev/disk/by-path/pci-0000:82:00.0-sas-phy3-lun-0
d8_b=/dev/disk/by-path/pci-0000:82:00.0-sas-phy4-lun-0
d8_c=/dev/disk/by-path/pci-0000:82:00.0-sas-phy7-lun-0
d6_a=/dev/disk/by-path/pci-0000:82:00.0-sas-phy2-lun-0
d6_b=/dev/disk/by-path/pci-0000:00:1f.2-ata-1.0

export POOL=testpool

clean_up() {
  if zpool status $POOL; then {
    zpool destroy $POOL
  } fi

  sgdisk --zap-all $d16_a &
  sgdisk --zap-all $d16_b &
  sgdisk --zap-all $d16_c &
  sgdisk --zap-all $d16_d &

  sgdisk --zap-all $d8_a &
  sgdisk --zap-all $d8_b &
  sgdisk --zap-all $d8_c &

  sgdisk --zap-all $d6_a &
  sgdisk --zap-all $d6_b &

  wait
}

make_whole_disk() {
  zpool create -f $POOL \
    raidz2 $d16_a $d16_b $d16_c $d16_d  $d8_a $d8_b $d8_c  $d6_a $d6_b
}

make_slices() {
  for d in $d16_a $d16_b $d16_c $d16_d  $d8_a $d8_b $d8_c  $d6_a $d6_b; do {
    sgdisk --align-end --new=1:0:+5723165M --typecode=1:bf01 $d &
  } done
  wait

  for d in $d16_a $d16_b $d16_c $d16_d  $d8_a $d8_b $d8_c; do {
    sgdisk --align-end --new=2:0:+1907719M --typecode=2:bf01 $d &
  } done
  wait

  for d in $d16_a $d16_b $d16_c $d16_d; do {
    sgdisk --align-end --new=3:0:+7628762M --typecode=3:bf01 $d &
  } done
  wait

  partprobe
  udevadm settle

  zpool create $POOL \
    raidz2 ${d16_a}-part1 ${d16_b}-part1 ${d16_c}-part1 ${d16_d}-part1  ${d8_a}-part1 ${d8_b}-part1 ${d8_c}-part1 ${d6_a}-part1 ${d6_b}-part1 \
    raidz2 ${d16_a}-part2 ${d16_b}-part2 ${d16_c}-part2 ${d16_d}-part2  ${d8_a}-part2 ${d8_b}-part2 ${d8_c}-part2 \
    raidz2 ${d16_a}-part3 ${d16_b}-part3 ${d16_c}-part3 ${d16_d}-part3
}

run_test() {
  local name="$1"
  local report="report-$(date +%s)-${name}.txt"
  fio --output="${report}" job.fio
}

ensure_root() {
  if [[ $EUID -ne 0 ]]; then {
    echo "Run as root!"
    exit 1
  } fi
}

main() {
  # whole disk
  clean_up
  make_whole_disk
  run_test whole

  # slices
  clean_up
  make_slices
  run_test slices

  # clean up
  clean_up
}

ensure_root
main
