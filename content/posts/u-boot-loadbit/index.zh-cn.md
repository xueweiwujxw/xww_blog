---
title: 'U-boot 加载 bit 文件'
date: 2024-05-29T10:44:04+08:00
lastmod: 2024-05-29T10:44:04+08:00
draft: false
author: 'wlanxww'
authorLink: 'https://wlanxww.com'
description: 'U-boot 加载 bit 文件'
images: []
resources:
  - name: 'featured-image'
    src: 'featured-image.png'
tags: ['xilinx', 'petalinux', 'u-boot']
categories: ['嵌入式系统']
---

**U-boot** 加载 bit 文件

<!--more-->

## 启用自定义 u-boot 环境变量

### 开启 bsp.cfg

> 参考 Xilinx 论坛 [75730 - 2020.x-2021.x PetaLinux: Why does platform-top.h not work in U-Boot distro boot](https://support.xilinx.com/s/article/75730?language=en_US)

- 添加文件`<project-dir>/project-spec/meta-user/recipes-bsp/u-boot/files/bsp.cfg`，内容如下：
  ```config
  CONFIG_SYS_CONFIG_NAME="platform-top"
  ```
- 修改`<project-dir>/project-spec/meta-user/recipes-bsp/u-boot/u-boot-xlnx_%.bbappend`，内容如下：

  ```bitbake
  FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

  SRC_URI_append += " \
  		file://platform-top.h \
  		file://bsp.cfg"

  do_configure_append () {
  	install ${WORKDIR}/platform-top.h ${S}/include/configs/
  }

  do_configure_append_microblaze () {
  	if [ "${U_BOOT_AUTO_CONFIG}" = "1" ]; then
  		install -d ${B}/source/board/xilinx/microblaze-generic/
  		install ${WORKDIR}/config.mk ${B}/source/board/xilinx/microblaze-generic/
  	fi
  }
  ```

### 修改 platform-top.h

> 参考 u-boot zynq 源码 [u-boot-xlnx/include/configs/zynq-common.h at xlnx_rebase_v2021.01_2021.1 · Xilinx/u-boot-xlnx](https://github.com/Xilinx/u-boot-xlnx/blob/xlnx_rebase_v2021.01_2021.1/include/configs/zynq-common.h)

- 修改`<project-dir>/project-spec/meta-user/recipes-bsp/u-boot/files/platform-top.h`，内容如下

  ```c
  #include <configs/zynq-common.h> // 文件来自 https://github.com/Xilinx/u-boot-xlnx/blob/xlnx_rebase_v2021.01_2021.1/include/configs/zynq-common.h

  #ifdef CONFIG_EXTRA_ENV_SETTINGS
  #undef CONFIG_EXTRA_ENV_SETTINGS
  #define CONFIG_EXTRA_ENV_SETTINGS                                                         \
      "scriptaddr=0x20000\0"                                                                \
      "script_size_f=0x40000\0"                                                             \
      "fdt_addr_r=0x1f00000\0"                                                              \
      "pxefile_addr_r=0x2000000\0"                                                          \
      "kernel_addr_r=0x2000000\0"                                                           \
      "scriptaddr=0x3000000\0"                                                              \
      "ramdisk_addr_r=0x3100000\0"                                                          \
      "bitload=fatload mmc 1:1 0x8000000 system.bit.bin; fpga load 0 0x8000000 $filesize\0" \
      "bootcmd=run bitload; run distro_bootcmd\0" BOOTENV
  #endif
  ```

  &emsp;&emsp;在原有代码的基础上，添加了`bitload=fatload mmc 1:1 0x8000000 system.bit.bin; fpga load 0 0x8000000 $filesize\0`，从 mmc1 的分区 1 读取 system.bit.bin，这里是因为我使用的 mmc 的序号是 1，并且将 bit.bin 放在了分区 1，分区 2 存放文件系统，分区和格式化可以参考[eMMC 分区]({{< ref "posts/emmc-partition/index.zh-cn.md" >}})和[Petalinux 双启动模式]({{< ref "posts/zynq-dual-boot/index.zh-cn.md" >}})，需要注意的是，fatload 只能读取 fat32 格式的文件系统，所以无论是 SD 卡启动还是 emmc 启动，都需要创建两个分区，下面是 sd 卡和 emmc 的分区显示。

  ```log
  root@zynq-kernel:~# fdisk -l /dev/mmcblk0
  Disk /dev/mmcblk0: 15 GB, 15931539456 bytes, 31116288 sectors
  61012 cylinders, 255 heads, 2 sectors/track
  Units: sectors of 1 * 512 = 512 bytes

  Device       Boot StartCHS    EndCHS        StartLBA     EndLBA    Sectors  Size Id Type
  /dev/mmcblk0p1    4,4,1       1023,254,2        2048   15628287   15626240 7630M  c Win95 FAT32 (LBA)
  /dev/mmcblk0p2    1023,254,2  1023,254,2    15628288   31115263   15486976 7562M 83 Linux
  root@zynq-kernel:~# fdisk -l /dev/mmcblk1
  Disk /dev/mmcblk1: 7456 MB, 7818182656 bytes, 15269888 sectors
  238592 cylinders, 4 heads, 16 sectors/track
  Units: sectors of 1 * 512 = 512 bytes

  Device       Boot StartCHS    EndCHS        StartLBA     EndLBA    Sectors  Size Id Type
  /dev/mmcblk1p1    0,1,1       1023,3,16           16    7634951    7634936 3727M  b Win95 FAT32
  /dev/mmcblk1p2    1023,3,16   1023,3,16      7634952   15269887    7634936 3727M 83 Linux
  ```

  &emsp;&emsp;`bootcmd`增加了对`bitload`的调用，这样实现了 boot 自动调用 bitload 加载 bit。SD 卡的分区 1 存放`BOOT.BIN`，`boot.scr`，`image.ub`，`system.bit.bin`，分区 2 存放文件系统，emmc 的分区 1 存放`system.bit.bin`，分区 2 存放文件系统，具体使用哪种方式看个人需求。
