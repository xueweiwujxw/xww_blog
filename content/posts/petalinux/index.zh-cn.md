---
title: "Petalinux eMMC 分区"
date: 2022-08-07T21:29:08+08:00
lastmod: 2022-08-07T21:29:08+08:00
draft: false
author: "wlanxww"
authorLink: "https://wlanxww.com"
description: "petalinux eMMC 配置"
tags: ["xilinx", "petalinux", "emmc"]
categories: ["嵌入式系统"]
---

**eMMC** 分区
<!--more-->

## 内核配置

&emsp;&emsp;启用dosfstools。
* `petalinux-config -c rootfs`
* `Filesystem Packages`->`utils`->`dosfstools`->`dosfstools`

## 分区与格式化

&emsp;&emsp;完整分区流程。
```log
root@petalinux:~# fdisk /dev/mmcblk0

The number of cylinders for this disk is set to 238592.
There is nothing wrong with that, but this is larger than 1024,
and could in certain setups cause problems with:
1) software that runs at boot time (e.g., old versions of LILO)
2) booting and partitioning software from other OSs
   (e.g., DOS FDISK, OS/2 FDISK)

Command (m for help): m  --- 获取使用说明
Command Action
a       toggle a bootable flag
b       edit bsd disklabel
c       toggle the dos compatibility flag
d       delete a partition
l       list known partition types
n       add a new partition
o       create a new empty DOS partition table
p       print the partition table
q       quit without saving changes
s       create a new empty Sun disklabel
t       change a partition's system id
u       change display/entry units
v       verify the partition table
w       write table to disk and exit

Command (m for help): p  --- 显示分区信息
Disk /dev/mmcblk0: 7456 MB, 7818182656 bytes, 15269888 sectors
238592 cylinders, 4 heads, 16 sectors/track
Units: sectors of 1 * 512 = 512 bytes

Device       Boot StartCHS    EndCHS        StartLBA     EndLBA    Sectors  Size Id Type

Command (m for help): n  --- 创建新的分区
Partition type
   p   primary partition (1-4)
   e   extended
p
Partition number (1-4): 1  --- 输入分区号
First sector (16-15269887, default 16):  --- 直接Enter，使用默认扇区
Using default value 16
Last sector or +size{,K,M,G,T} (16-15269887, default 15269887):  --- 直接Enter，全部使用，需要的话可以根据大小输入 +size{,K,M,G,T}
Using default value 15269887

Command (m for help): t  --- 修改分区id
Selected partition 1
Hex code (type L to list codes): L   --- 列出所有的类型

 0 Empty                  1c Hidden W95 FAT32 (LBA) a0 Thinkpad hibernation
 1 FAT12                  1e Hidden W95 FAT16 (LBA) a5 FreeBSD
 4 FAT16 <32M             3c Part.Magic recovery    a6 OpenBSD
 5 Extended               41 PPC PReP Boot          a8 Darwin UFS
 6 FAT16                  42 SFS                    a9 NetBSD
 7 HPFS/NTFS              63 GNU HURD or SysV       ab Darwin boot
 a OS/2 Boot Manager      80 Old Minix              af HFS / HFS+
 b Win95 FAT32            81 Minix / old Linux      b7 BSDI fs
 c Win95 FAT32 (LBA)      82 Linux swap             b8 BSDI swap
 e Win95 FAT16 (LBA)      83 Linux                  be Solaris boot
 f Win95 Ext'd (LBA)      84 OS/2 hidden C: drive   eb BeOS fs
11 Hidden FAT12           85 Linux extended         ee EFI GPT
12 Compaq diagnostics     86 NTFS volume set        ef EFI (FAT-12/16/32)
14 Hidden FAT16 <32M      87 NTFS volume set        f0 Linux/PA-RISC boot
16 Hidden FAT16           8e Linux LVM              f2 DOS secondary
17 Hidden HPFS/NTFS       9f BSD/OS                 fd Linux raid autodetect
1b Hidden Win95 FAT32
Hex code (type L to list codes): b --- 选择Win95 FAT32
Changed system type of partition 1 to b (Win95 FAT32)

Command (m for help): w  --- 保存分区表写入eMMC并退出
The partition table has been altered.
Calling ioctl() to re-read partition table
 mmcblk0: p1
root@petalinux:~#  mmcblk0: p1 --- 系统输出的eMMC的分区信息
```
&emsp;&emsp;格式化

&emsp;&emsp;`mkdosfs /dev/mmcblk0p1`，`/dev/mmcblk0p1`是分区后生成的字符设备。

## 挂载(可选)

&emsp;&emsp;`mount /dev/mmcblk0p1 /mnt`，根据系统的不同，是否默认挂载以及挂载位置均有可能不同。本次默认挂载的位置是`/media/sd-mmcblk0p1`，可通过`mount`查看挂载信息。
