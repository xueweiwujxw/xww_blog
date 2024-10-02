---
title: 'U-boot 加载 bit 文件'
date: 2024-05-29T10:44:04+08:00
lastmod: 2024-10-02T20:47:58+08:00
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

### 添加自定义 postconfig

#### 为什么要自定义 `postconfig`

当按照上述步骤添加 `u-boot` 阶段的 bit 文件加载之后，会提示需要手动执行 `postconfig`

```
INFO:post config was not run, please run manually if needed
```

这里说明在 `u-boot` 阶段通过指令加载 bit 文件之后，需要执行 `postconfig` 来配置相关的设置，一个具体的例子就是 dma 的配置，在 zynq ip 核的配置中，dma 的数据位宽默认配置是 64 位，如果需要使用 32 位，就需要修改配置，修改完成后导出硬件描述文件`.xsa`文件，并导入到 petalinux 工程，最终生成下面的配置文件

```
project-spec/hw-description
├── metadata
├── ps7_init.c
├── ps7_init_gpl.c
├── ps7_init_gpl.h
├── ps7_init.h
├── ps7_init.html
├── ps7_init.tcl
└── system.xsa

0 directories, 8 files
```

其中`ps7_init_gpl.c`、`ps7_init_gpl.h`、`ps7_init.c`、`ps7_init.h`包含了寄存器配置，详细内容可以查看`ps7_init.html`。这样就有一个思路，可以把这个文件加入到 `u-boot` 的源码中，然后添加一个 cmd 作为 `u-boot` 的指令，并按照上述修改 `bootcmd` 的方式，将 `postconfig` 作为启动的一个步骤。

但是在此之前，我们回到最初的起点，我们导出的 `xsa` 文件并没有包含 bit 文件，但是如果按照 xilinx 的文档，其实是需要包含 bit 文件的，并且也不会出现在 `u-boot` 阶段提示需要手动执行 postconfig，那么为什么 `u-boot` 手动加载 bit 文件就需要执行 `postconfig` 呢，我们可以从[xilinx 的 embeddedsw 项目中关于 zyqn_fsbl 的代码中](https://github.com/Xilinx/embeddedsw/blob/xilinx_v2021.1/lib/sw_apps/zynq_fsbl/src/main.c)找到答案。

在[代码 150 行](https://github.com/Xilinx/embeddedsw/blob/xilinx_v2021.1/lib/sw_apps/zynq_fsbl/src/main.c#L150)可以看到声明一个外部的函数

```
extern int ps7_post_config();
```

这个函数的实现可以在`ps7_init_gpl.c`和`ps7_init.c`找到，可以猜想到，`fsbl` 是通过 `xsa` 文件读取到的 `post_config` 对寄存器配置的，这一点可以通过[Makefile 的第 18 行](https://github.com/Xilinx/embeddedsw/blob/xilinx_v2021.1/lib/sw_apps/zynq_fsbl/src/Makefile#L18C1-L18C10)得到验证，不过这里的 `BSP_DIR` 和 `BOARD` 是 xilinx 自己的开发板。

```makefile
c_SOURCES += $(BSP_DIR)/$(BOARD)/ps7_init.c
```

但是目前我们还是无法确定，为什么不加 bit，就不会执行 `postconfig`，继续看 `fsbl` 的代码，在[707 行 FsblHandoff 函数](https://github.com/Xilinx/embeddedsw/blob/xilinx_v2021.1/lib/sw_apps/zynq_fsbl/src/main.c#L707)中解答了这个问题。

```c
void FsblHandoff(u32 FsblStartAddr)
{
	u32 Status;

	/*
	 * Enable level shifter
	 */
	if(BitstreamFlag) {
		/*
		 * FSBL will not enable the level shifters for a NON PS instantiated
		 * Bitstream
		 * CR# 671028
		 * This flag can be set during compilation for a NON PS instantiated
		 * bitstream
		 */
#ifndef NON_PS_INSTANTIATED_BITSTREAM
#ifdef PS7_POST_CONFIG
		ps7_post_config();
		/*
		 * Unlock SLCR for SLCR register write
		 */
		SlcrUnlock();
#else
	/*
	 * Set Level Shifters DT618760
	 */
	Xil_Out32(PS_LVL_SHFTR_EN, LVL_PL_PS);
	fsbl_printf(DEBUG_INFO,"Enabling Level Shifters PL to PS "
			"Address = 0x%x Value = 0x%x \n\r",
			PS_LVL_SHFTR_EN, Xil_In32(PS_LVL_SHFTR_EN));

	/*
	 * Enable AXI interface
	 */
	Xil_Out32(FPGA_RESET_REG, 0);
	fsbl_printf(DEBUG_INFO,"AXI Interface enabled \n\r");
	fsbl_printf(DEBUG_INFO, "FPGA Reset Register "
			"Address = 0x%x , Value = 0x%x \r\n",
			FPGA_RESET_REG ,Xil_In32(FPGA_RESET_REG));
#endif
#endif
	}

	/*
	 * FSBL user hook call before handoff to the application
	 */
	Status = FsblHookBeforeHandoff();
	if (Status != XST_SUCCESS) {
		fsbl_printf(DEBUG_GENERAL,"FSBL_HANDOFF_HOOK_FAIL\r\n");
 		OutputStatus(FSBL_HANDOFF_HOOK_FAIL);
		FsblFallback();
	}

#ifdef XPAR_XWDTPS_0_BASEADDR
	XWdtPs_Stop(&Watchdog);
#endif

	/*
	 * Clear our mark in reboot status register
	 */
	ClearFSBLIn();

	if(FsblStartAddr == 0) {
		/*
		 * SLCR lock
		 */
		SlcrLock();

		fsbl_printf(DEBUG_INFO,"No Execution Address JTAG handoff \r\n");
		FsblHandoffJtagExit();
	} else {
		fsbl_printf(DEBUG_GENERAL,"SUCCESSFUL_HANDOFF\r\n");
		OutputStatus(SUCCESSFUL_HANDOFF);
		FsblHandoffExit(FsblStartAddr);
	}

	OutputStatus(ILLEGAL_RETURN);

	FsblFallback();
}
```

可以看到如果没有 `BitstreamFlag`，就不会执行 `post_config`，根据注释可以得知这是在编译的时候确定的，所以未包含 bit 的 `xsa` 文件会导致 `post_config` 无法正确执行。

#### 添加 postconfig

知晓了为什么需要添加 postconfig，就需要在 u-boot 阶段加上这个函数的执行。

在 u-boot-xlnx 的源码中，以 xilinx 的开发板源码为起点，可以找到[`cmds.c`](https://github.com/Xilinx/u-boot-xlnx/blob/xlnx_rebase_v2021.01/board/xilinx/zynq/cmds.c)和对应的[`Makefile`](https://github.com/Xilinx/u-boot-xlnx/blob/xlnx_rebase_v2021.01/board/xilinx/zynq/Makefile)。

`cmds.c` 通过宏`U_BOOT_CMD`实现了自定义的 `u-boot` 指令，根据 `ps7_post_config()`的函数定义，添加如下代码

```c
static int do_ps7_fpga_post_config(struct cmd_tbl *cmdtp, int flag, int argc,
							  char *const argv[]) {
	puts("INFO:run board ps7 post config\n");
	return ps7_post_config();
}

U_BOOT_CMD(
	postconfig, 1, 0, do_ps7_fpga_post_config,
	"run ps7 post config after fpga load bin file",
	"");
```

这样就添加一个名为 `postconfig` 的自定义指令，执行的函数是 `do_ps7_fpga_post_config`，最终调用了 `ps7_post_config()`，当然单独添加指令无用，可以参考[zynq_zc702 的代码](https://github.com/Xilinx/u-boot-xlnx/tree/xlnx_rebase_v2021.01/board/xilinx/zynq/zynq-zc702)，这里面加入了 `ps7_init_gpl.c`，所以我们可以添加头文件`#include "ps7_init_gpl.h"`，理论上也可以采用 extern 的方式声明，可以自行尝试。

Makefile 说明了`ps_init_gpl.c`的编译过程，提示将`ps7_init_gpl.c/h`放在`board/xilinx/zynq/custom_hw_platform/`，并且需要开启`CONFIG_XILINX_PS_INIT_FILE`，这个配置可以在[Kconfig](https://github.com/Xilinx/u-boot-xlnx/blob/xlnx_rebase_v2021.01/board/xilinx/Kconfig)找到，最终将 Makefile 改为如下形式

```makefile
# SPDX-License-Identifier: GPL-2.0+
#
# (C) Copyright 2000-2006
# Wolfgang Denk, DENX Software Engineering, wd@denx.de.

obj-y	:= board.o

ifneq ($(CONFIG_XILINX_PS_INIT_FILE),"")
PS_INIT_FILE := $(shell cd $(srctree); readlink -f $(CONFIG_XILINX_PS_INIT_FILE))
init-objs := ps_init_gpl.o
spl/board/xilinx/zynq/ps_init_gpl.o board/xilinx/zynq/ps_init_gpl.o: $(PS_INIT_FILE)
	$(CC) $(c_flags) -I $(srctree)/$(src) -c -o $@ $^
endif

DEVICE_TREE ?= $(CONFIG_DEFAULT_DEVICE_TREE:"%"=%)
ifeq ($(DEVICE_TREE),)
DEVICE_TREE := unset
endif

ifeq ($(init-objs),)
hw-platform-y :=$(shell echo $(DEVICE_TREE))
init-objs := $(if $(wildcard $(srctree)/$(src)/$(hw-platform-y)/ps7_init_gpl.c),\
	$(hw-platform-y)/ps7_init_gpl.o)
endif

ifeq ($(init-objs),)
ifneq ($(wildcard $(srctree)/$(src)/ps7_init_gpl.c),)
init-objs := ps7_init_gpl.o
$(if $(CONFIG_SPL_BUILD),\
$(warning Put custom ps7_init_gpl.c/h to board/xilinx/zynq/custom_hw_platform/))
endif
endif

obj-y += $(init-objs)

ifndef CONFIG_SPL_BUILD
obj-$(CONFIG_CMD_ZYNQ) += cmds.o
obj-$(CONFIG_CMD_ZYNQ_RSA) += bootimg.o
endif

# Suppress "warning: function declaration isn't a prototype"
CFLAGS_REMOVE_ps7_init_gpl.o := -Wstrict-prototypes

# To include xil_io.h
CFLAGS_ps7_init_gpl.o := -I$(srctree)/$(src)
```

{{< admonition type=notice title="提示" open=true >}}
这里为什么是`ps7_init_gpl.c`而不是`ps7_init.c`，目前不清楚原因，但是可以参考两者的代码，基本上一致，所以按照 xilinx 的 u-boot 源码选择`ps7_init_gpl.c`，
{{< /admonition >}}

现在还差最后一步，怎样将我们的`ps7_init_gpl.c/h`加入到 `u-boot` 源码并添加指令。我们可以借助`project-spec/meta-user/recipes-bsp/u-boot/`的`u-boot-xlnx_%.bbappend`，将代码 install 到 `u-boot` 的源码。

```bitbake
FILESEXTRAPATHS_prepend := "${THISDIR}/files:${THISDIR}/../../../hw-description:"

SRC_URI_append += " \
		file://fpga_post_config.patch \
		file://platform-top.h \
		file://ps7_init_gpl.h \
		file://ps7_init_gpl.c \
		file://bsp.cfg"

do_configure_append () {
	install ${WORKDIR}/platform-top.h ${S}/include/configs/
	mkdir -p ${S}/board/xilinx/zynq/custom_hw_platform
	install ${WORKDIR}/ps7_init_gpl.c ${S}/board/xilinx/zynq/custom_hw_platform/
	install ${WORKDIR}/ps7_init_gpl.h ${S}/board/xilinx/zynq/
}

do_configure_append_microblaze () {
	if [ "${U_BOOT_AUTO_CONFIG}" = "1" ]; then
		install -d ${B}/source/board/xilinx/microblaze-generic/
		install ${WORKDIR}/config.mk ${B}/source/board/xilinx/microblaze-generic/
	fi
}
SRC_URI += "file://user_2024-07-15-10-44-00.cfg"
```

`ps7_init_gpl.h/c` 是在 `hw_description` 目录下，为了不复制多余的文件，直接将 `hw_description` 目录添加进来，然后根据 Makefile 中的提示，将文件添加到`board/xilinx/zynq/custom_hw_platform/`，`user_2024-07-15-10-44-00.cfg` 是 Kconfig 的配置，可以通过`petalinux-config -c u-boot`直接搜索`XILINX_PS_INIT_FILE`，并将`board/xilinx/zynq/custom_hw_platform/ps7_init_gpl.c`填入。

`platform-top.h`添加 `postconfig` 指令

```c
    "bootcmd=run bitload; postconfig; run distro_bootcmd\0" BOOTENV
```

#### 所有修改的文件

##### user\_{datetime}.cfg

```
CONFIG_XILINX_PS_INIT_FILE="board/xilinx/zynq/custom_hw_platform/ps7_init_gpl.c"
```

##### fpga_post_config.patch

```diff
diff --git a/board/xilinx/zynq/Makefile b/board/xilinx/zynq/Makefile
index 8566171589..792643ab11 100644
--- a/board/xilinx/zynq/Makefile
+++ b/board/xilinx/zynq/Makefile
@@ -31,13 +31,13 @@ $(warning Put custom ps7_init_gpl.c/h to board/xilinx/zynq/custom_hw_platform/))
 endif
 endif

+obj-y += $(init-objs)
+
 ifndef CONFIG_SPL_BUILD
 obj-$(CONFIG_CMD_ZYNQ) += cmds.o
 obj-$(CONFIG_CMD_ZYNQ_RSA) += bootimg.o
 endif

-obj-$(CONFIG_SPL_BUILD) += $(init-objs)
-
 # Suppress "warning: function declaration isn't a prototype"
 CFLAGS_REMOVE_ps7_init_gpl.o := -Wstrict-prototypes

diff --git a/board/xilinx/zynq/cmds.c b/board/xilinx/zynq/cmds.c
index 73e2b0eac7..aa7d8d5091 100644
--- a/board/xilinx/zynq/cmds.c
+++ b/board/xilinx/zynq/cmds.c
@@ -18,6 +18,7 @@
 #include <zynqpl.h>
 #include <fpga.h>
 #include <zynq_bootimg.h>
+#include "ps7_init_gpl.h"

 DECLARE_GLOBAL_DATA_PTR;

@@ -550,3 +551,14 @@ static char zynq_help_text[] =
 U_BOOT_CMD(zynq,	6,	0,	do_zynq,
 	   "Zynq specific commands", zynq_help_text
 );
+
+static int do_ps7_fpga_post_config(struct cmd_tbl *cmdtp, int flag, int argc,
+							  char *const argv[]) {
+	puts("INFO:run board ps7 post config\n");
+	return ps7_post_config();
+}
+
+U_BOOT_CMD(
+	postconfig, 1, 0, do_ps7_fpga_post_config,
+	"run ps7 post config after fpga load bin file",
+	"");

```

##### platform-top.h

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
    "bitload=fatload mmc 0:1 0x8000000 system.bit.bin; fpga load 0 0x8000000 $filesize\0" \
    "bootcmd=run bitload; postconfig; run distro_bootcmd\0" BOOTENV
#endif
```

##### u-boot-xlnx\_%.bbappend

```bitbake
FILESEXTRAPATHS_prepend := "${THISDIR}/files:${THISDIR}/../../../hw-description:"

SRC_URI_append += " \
		file://fpga_post_config.patch \
		file://platform-top.h \
		file://ps7_init_gpl.h \
		file://ps7_init_gpl.c \
		file://bsp.cfg"

do_configure_append () {
	install ${WORKDIR}/platform-top.h ${S}/include/configs/
	mkdir -p ${S}/board/xilinx/zynq/custom_hw_platform
	install ${WORKDIR}/ps7_init_gpl.c ${S}/board/xilinx/zynq/custom_hw_platform/
	install ${WORKDIR}/ps7_init_gpl.h ${S}/board/xilinx/zynq/
}

do_configure_append_microblaze () {
	if [ "${U_BOOT_AUTO_CONFIG}" = "1" ]; then
		install -d ${B}/source/board/xilinx/microblaze-generic/
		install ${WORKDIR}/config.mk ${B}/source/board/xilinx/microblaze-generic/
	fi
}
SRC_URI += "file://user_2024-07-15-10-44-00.cfg"

```
