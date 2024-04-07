---
title: 'Petalinux 双启动模式'
date: 2024-04-07T17:29:30+08:00
lastmod: 2024-04-07T17:29:30+08:00
draft: false
author: 'wlanxww'
authorLink: 'https://wlanxww.com'
description: 'Petalinux 双启动模式'
images: []
resources:
  - name: 'featured-image'
    src: 'featured-image.png'
tags: ['xilinx', 'petalinux', 'boot']
categories: ['嵌入式系统']
---

**Petalinux** 双启动模式

<!--more-->

## 文件系统配置

### 设置文件系统

&emsp;&emsp;

- `petalinux-config` -> `Image Packaging Configuration` -> `Root filesystem type`，选择`EXT4`。
- `Device node of SD device`暂时设置为`/dev/mmcblk0p2`，后续需要修改为指定的 emmc 的分区，目前是 sd 的分区。

### sd 卡分区

- 在 linux 上使用分区工具，将 sd 卡分成两个区，一个是`fat32`格式，用于存放`BOOT.BIN`，`boot.scr`，`image.ub`，另一个是`ext4`格式，存放文件系统，分区大小可以自行指定。下面是进入到系统之后的分区情况，仅作为参考。

  ```log
  Disk /dev/mmcblk0: 15 GB, 15634268160 bytes, 30535680 sectors
  59873 cylinders, 255 heads, 2 sectors/track
  Units: sectors of 1 * 512 = 512 bytes

  Device       Boot StartCHS    EndCHS        StartLBA     EndLBA    Sectors  Size Id Type
  /dev/mmcblk0p1    4,4,1       1023,254,2        2048   15628287   15626240 7630M  c Win95 FAT32 (LBA)
  /dev/mmcblk0p2    1023,254,2  1023,254,2    15628288   30535679   14907392 7279M 83 Linux
  Disk /dev/mmcblk1: 7456 MB, 7818182656 bytes, 15269888 sectors
  238592 cylinders, 4 heads, 16 sectors/track
  Units: sectors of 1 * 512 = 512 bytes
  ```

- 将`BOOT.BIN`，`boot.scr`，`image.ub`复制到第一个分区，将`rootfs.cpio`复制到第二个分区。然后打开终端进入对应分区目录，输入下面的命令解压，没有`pax`就去装一个，一般安装 petalinux 会要求安装 pax。

  ```bash
  sudo pax -rvf rootfs.cpio
  ```

- 安装 sd 卡，操作正确可以进入系统。

## emmc 分区设置

### 编译 mkfs

- petalinux 的 rootfs 中自带的 mkfs 的代码可能存在问题，没有正确执行过，下载[mkfs 源码 https://github.com/tytso/e2fsprogs/tree/v1.47.0](https://github.com/tytso/e2fsprogs/tree/v1.47.0)，通过下面的指令配置编译。
  ```bash
  ./configure --prefix=/usr/arm-linux-gnueabihf --host=arm-linux-gnueabihf CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++
  make -j
  ```

### 格式化 emmc

- 将编译好的`misc/mke2fs`复制到 zynq 系统中，根据[eMMC 分区]({{< ref "posts/emmc-partition/index.zh-cn.md" >}})对 emmc 进行分区，默认创建新的分区后就是 linux 文件系统，不需要执行之后的更改 id 的操作，保存分区表退出即可，然后执行`./mke2fs -t ext4 /dev/mmcblk1p1`，`/dev/mmcblk1p1`根据当前设备自行调整。正确操作后，执行`fdisk -l`，应该可以看到如下输出。
  ```log
  Device       Boot StartCHS    EndCHS        StartLBA     EndLBA    Sectors  Size Id Type
  /dev/mmcblk1p1    0,1,1       1023,3,16           16   15269887   15269872 7455M 83 Linux
  ```
  挂载`/dev/mmcblk1p1`，应该可以看到挂载的设备类型是 ext4。
  ```log
  /dev/mmcblk1p1 on /media/sd-mmcblk1p1 type ext4 (rw,relatime)
  ```

## qspi-emmc 系统配置

### emmc 文件系统写入

- 修改`Device node of SD device`为`/dev/mmcblk1p1`(这个设备对应 emmc 格式化之后的设备)，并重新编译。
- 挂载`/dev/mmcblk1p1`
- 将`rootfs.cpio`复制到挂载的目录中并进入该目录，在其中执行`cpio -idmv < rootfs.cpio`，正确解压即可

### qspi 烧写

- 进入 u-boot 依次执行系列操作（需要提前自行配置好 tftpboot，并确保编译打包好的产物在`/tftpboot/`内）
  ```bash
  setenv ipaddr 192.168.0.10                   # 设置本地ip
  setenv serverip 192.168.0.1                  # 设置tftp服务器ip
  sf probe                                     # 挂载qspi设备
  sf erase 0x0 0x4000000                       # 擦除需要写入的分区，大小根据config中的配置调整
  tftpboot 0x80000 BOOT.BIN                    # 下载BOOT.BIN
  sf write 0x80000 0x0 <sizeof BOOT.BIN>       # 写入BOOT.BIN，大小根据BOOT.BIN写入
  tftpboot 0x80000 boot.scr                    # 下载boot.scr
  sf write 0x80000 0xfc0000 <sizeof boot.scr>  # 写入boot.scr，大小根据boot.scr写入
  tftpboot 0x80000 image.ub                    # 下载image.ub
  sf write 0x80000 0x1000000 <sizeof image.ub> # 写入image.ub，大小根据image.ub写入
  ```
- 拔出 sd 卡（可选，最好拔出，验证是否正确），重新上电，操作正确可进入系统。

## 文件系统切换

&emsp;&emsp;按照上述的步骤最终可以得到一个启动方式分别为 sd 和 qspi 的系统，但是文件系统均挂载到 emmc 中，这是因为正常使用不使用 sd 模式，但是可以通过 u-boot 切换到 sd 卡的文件系统。

### u-boot 切换

```shell
setenv bootargs "console=ttyPS0,115200 earlycon root=/dev/mmcblk0p2 rw rootwait"  ## /dev/mmcblk0p2 替换为需要的文件系统挂载设备
boot
```

## SD 卡安装新系统

&emsp;&emsp;在上面的步骤中，已经得到了一个能运行 petalinux 的 sd 卡，根据这张 sd 卡可以在一个新开发板中安装系统。

### 进入 sd 卡系统

- 拨码开关切换到 sd 卡模式。
- 进入 u-boot，根据[文件系统切换](#文件系统切换)，将文件系统挂载的位置切换到 sd 卡中，本例为`/dev/mmcblk0p2`，若默认为 sd 卡，则不需要进行切换。

### 设置 emmc

- 根据[emmc 分区设置](#emmc-分区设置)，完成对 emmc 的分区和格式化
- 根据[qspi-emmc 系统配置](#qspi-emmc-系统配置)，完成对 qspi 和 emmc 的烧写

### 进入 emmc 系统

- 拨码开关切换到 qspi 模式
- 拔出 sd 卡并上电，能够进入系统则说明安装成功
