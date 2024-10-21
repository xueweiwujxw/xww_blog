---
title: 'zynmp系统调试踩的坑'
date: 2022-07-22T00:04:29+08:00
lastmod: 2024-10-21T20:29:13+08:00
draft: false
author: 'wlanxww'
authorLink: 'https://wlanxww.com'
description: 'petalinux调试'
images: []
resources:
  - name: 'featured-image'
    src: 'featured-image.png'
tags: ['xilinx', 'petalinux', 'zynqmp']
categories: ['嵌入式系统']
---

**zynqmp** 系统调试记录

<!--more-->

## 调试环境

### 系统环境

- Ubuntu 20.04

### 软件环境

- Vivado 2021.1
- Petalinux 2021.1

## 构建系统

### 生成 Vivado 工程

&emsp;&emsp;根据原理图选择对应的 part 创建 vivado 工程，添加新的 block design，添加 zynqmp ip 核。

### IP 核配置

&emsp;&emsp;连接方式参考原理图，因为是公司的项目就不放图了。

&emsp;&emsp;这里需要注意的一个坑是 dp 的 lane 连接，对于仅用了一个 lane 的 dp，根据原理图选择对应的 MIO 即可，但是如果使用了两个 lane，需要注意`DP Lane0`、`DP Lane1`与`GT Lane1`、`GT Lane0`的对应关系，这是选择`Dual Lower`的情况，如果是`Dual Higher`，应该是`GT Lane3`、`GT Lane2`，同时需要留意原理图上是不是一样的对应关系，一定要按照 Xilinx 的参考设计。

&emsp;&emsp;个人分析原因应该是在 zynqmp 配置的时候连接是反的，所以原理图上连接到转换芯片上时也需要反过来，总之是一个很容易忽略的细节。这里附上我在 Xilinx 论坛的[提问链接](https://support.xilinx.com/s/question/0D52E00007H423JSAR/zynqmp-displayport-issue)

### 生成 Petalinux 系统

&emsp;&emsp;生成系统没什么好说的，根据 petalinux 文档操作即可，注意选择正确的`template`，zynqmp 自然是选择`zynqMP`。导入 vivado 编译生成的`xsa`文件，然后编译一次，petalinux 自己生成设备树，方便后续修改。

> [!NOTE]+ 提示
> &emsp;&emsp;因为 Petalinux 每次编译会从服务器下载`xlnx`的源码，所以建议自己配置一个本地服务器或者公司内网使用的服务器，推荐后者。<br>
> 编辑 Petalinux 的`Yocto`设置，启用`YOCTO_NETWORK_SSTATE_FEEDS`，并设置`YOCTO_NETWORK_SSTATE_FEEDS_URL`为配置好的服务器地址，这样可以大幅减少第一次编译的时间，配置服务器之后会写另外一篇博客，更新后回附上链接。
> `project-spec/configs/config`部分内容如下
>
> ```
> CONFIG_YOCTO_NETWORK_SSTATE_FEEDS=y
>
> #
> # Network sstate feeds URL
> #
> CONFIG_YOCTO_NETWORK_SSTATE_FEEDS_URL="http://petamirror.com:12333/sswreleases/rel-v2021/aarch64/sstate-cache"
> ```

## 接口调试

### 网口调试

&emsp;&emsp;网口调试更依赖与选择的芯片以及连接方式，这次使用的芯片配置比较简单，并且直接连在了 PS 端，所以仅声明一下`phy-handle`以及寄存器地址即可。

```dts
&gem0 {
	status = "okay";
	phy-mode = "rgmii-id";
	phy-handle = <&ethernet_phy0>;
	ethernet_phy0: ethernet-phy@0 {
		reg = <0>;
        led-reg-value = <0x0088>;
	};
};
```

&emsp;&emsp;配置完成后网口`10Mbps`，`100Mbps`，`1000Mbps`都可以正常工作，但是网口的指示灯不符合常用习惯，所以我在驱动中添加了`led-reg-value`的代码，根据手册设置指示灯的颜色。

```diff
diff --git a/drivers/net/phy/marvell.c b/drivers/net/phy/marvell.c
index 5aec673a0120..024c4a5d4dcc 100644
--- a/drivers/net/phy/marvell.c
+++ b/drivers/net/phy/marvell.c
@@ -664,6 +664,10 @@ static int m88e1510_config_aneg(struct phy_device *phydev)

 static void marvell_config_led(struct phy_device *phydev)
 {
+	u16 led_reg_value;
+	int ret;
+	struct device_node *np = phydev->mdio.dev.of_node;
+
 	u16 def_config;
 	int err;

@@ -688,6 +692,14 @@ static void marvell_config_led(struct phy_device *phydev)
 		return;
 	}

+	ret = of_property_read_u16(np, "led-reg-value", &led_reg_value);
+	if (ret) {
+		phydev_info(phydev, "No custom led reg value, set default value\n");
+	} else {
+		def_config = led_reg_value;
+		phydev_info(phydev, "Set custom led reg value%d\n", led_reg_value);
+	}
+
 	err = phy_write_paged(phydev, MII_MARVELL_LED_PAGE, MII_PHY_LED_CTRL,
 			      def_config);
 	if (err < 0)
```

### USB 调试

&emsp;&emsp;Petalinux2021.1 中 USB 的配置已经很简单了，zynqmp ip 核按照原理图正确配置后，一般可以直接自动生成正确的设备树。但是由于都使用了 dwc3 的驱动，usb2.0 存在问题，Petalinux2021.2 修复了这个问题，我摘取了其中有关 usb 的代码，直接添加到当前工程的 patch 中。

```diff
diff --git a/drivers/usb/dwc3/dwc3-xilinx.c b/drivers/usb/dwc3/dwc3-xilinx.c
index 7231c5a3eece..85bb308959fb 100644
--- a/drivers/usb/dwc3/dwc3-xilinx.c
+++ b/drivers/usb/dwc3/dwc3-xilinx.c
@@ -374,14 +374,6 @@ static int dwc3_xlnx_init_zynqmp(struct dwc3_xlnx *priv_data)
 	u32			reg;
 	struct gpio_desc	*reset_gpio = NULL;

-	usb3_phy = devm_phy_get(dev, "usb3-phy");
-	if (PTR_ERR(usb3_phy) == -EPROBE_DEFER) {
-		ret = -EPROBE_DEFER;
-		goto err;
-	} else if (IS_ERR(usb3_phy)) {
-		usb3_phy = NULL;
-	}
-
 	crst = devm_reset_control_get_exclusive(dev, "usb_crst");
 	if (IS_ERR(crst)) {
 		ret = PTR_ERR(crst);
@@ -407,6 +399,15 @@ static int dwc3_xlnx_init_zynqmp(struct dwc3_xlnx *priv_data)
 		goto err;
 	}

+	usb3_phy = devm_phy_get(dev, "usb3-phy");
+	if (PTR_ERR(usb3_phy) == -EPROBE_DEFER) {
+		ret = -EPROBE_DEFER;
+		goto err;
+	} else if (IS_ERR(usb3_phy)) {
+		ret = 0;
+		goto skip_usb3_phy;
+	}
+
 	ret = reset_control_assert(crst);
 	if (ret < 0) {
 		dev_err(dev, "Failed to assert core reset\n");
@@ -461,17 +462,7 @@ static int dwc3_xlnx_init_zynqmp(struct dwc3_xlnx *priv_data)
 		goto err;
 	}

-	/*
-	 * This routes the USB DMA traffic to go through FPD path instead
-	 * of reaching DDR directly. This traffic routing is needed to
-	 * make SMMU and CCI work with USB DMA.
-	 */
-	if (of_dma_is_coherent(dev->of_node) || device_iommu_mapped(dev)) {
-		reg = readl(priv_data->regs + XLNX_USB_TRAFFIC_ROUTE_CONFIG);
-		reg |= XLNX_USB_TRAFFIC_ROUTE_FPD;
-		writel(reg, priv_data->regs + XLNX_USB_TRAFFIC_ROUTE_CONFIG);
-	}
-
+skip_usb3_phy:
 	/* ulpi reset via gpio-modepin or gpio-framework driver */
 	reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_HIGH);
 	if (IS_ERR(reset_gpio)) {
@@ -488,6 +479,17 @@ static int dwc3_xlnx_init_zynqmp(struct dwc3_xlnx *priv_data)
 		usleep_range(5000, 10000); /* delay */
 	}

+	/*
+	 * This routes the USB DMA traffic to go through FPD path instead
+	 * of reaching DDR directly. This traffic routing is needed to
+	 * make SMMU and CCI work with USB DMA.
+	 */
+	if (of_dma_is_coherent(dev->of_node) || device_iommu_mapped(dev)) {
+		reg = readl(priv_data->regs + XLNX_USB_TRAFFIC_ROUTE_CONFIG);
+		reg |= XLNX_USB_TRAFFIC_ROUTE_FPD;
+		writel(reg, priv_data->regs + XLNX_USB_TRAFFIC_ROUTE_CONFIG);
+	}
+
 err:
 	return ret;
 }
```

&emsp;&emsp;除了自动生成的设备树，需要指定 usb phy 的工作模式以及最大速度，对于 usb3，需要启用`lpm`(不启用也可以，只不过内核会报`warning`，强迫症难受)

```dts
&dwc3_0 {
    dr_mode = "host";
	maximum-speed = "high-speed"; /* usb 2.0 */
    snps,usb3_lpm_capable;
};

&dwc3_1 {
    dr_mode = "host";
	maximum-speed = "super-speed"; /* usb 3.0 */
    snps,usb3_lpm_capable;
};
```

### SD 卡调试

&emsp;&emsp;SD 卡主要出现了两个问题。

&emsp;&emsp;第一，SD 卡识别报错`Buffer I/O error on dev mmcblk0, logical block 0, async page read`，根据[论坛的描述](https://support.xilinx.com/s/article/73079?language=en_US)，这是一个在 2019.2 就存在的问题，需要在设备树中声明`no-1-8-v;`，声明后注意 sd 的供电电压。

&emsp;&emsp;第一，SD 卡无法写入，这是因为 zynqmp 中似乎默认设置了 SD 的写保护模式，需要在设备树中声明不启用。

```dts
&sdhci0 {
    no-1-8-v;
    disable-wp;
};
```

### DP 调试

&emsp;&emsp;DP 一开始报错`Invalid reference clock number`，在设备树中修改`psgtr`，指定 video_clk 以及 dp_aclk 的参考钟，具体需要参考自动生成的设备树以及 IP 核配置。

```dts
&psgtr {
    clocks = <&video_clk>, <&dp_aclk>;
    clock-names = "ref0", "ref3";
};
```

&emsp;&emsp;解决上述问题后，内核报错时钟和速率不匹配，并且驱动报错`More than allowed devices are using the vpll_int, which is forbidden`，参考 zynqmp IP 核的样例工程，修改了 DP 使用的输出时钟，解决了后者报错。通过`modetest -M xlnx`发现`Encoders`、`Connectors`、`CRTCs`、`Planes`的对应关系错误，并且`Connectors`的状态是`disconnected`，示波器查看 dp 的 aux 输出是反的，原因在于 MIO 数量不足，所以 dp 连在了 PL 端，通过 EMIO 连接到 arm，而文档中提到了`dp_aux_data_oe`连接到 EMIO 的极性会反转，这是我一开始忽略的地方，手动取反之后，`modetest`的测试结果正常。但是此时显示器依旧没有输出。这里就是上文提到的`DP Lane`与`GT Lane`的对应关系的问题了。

&emsp;&emsp;在调试的过程中，参考其他人的设备树，修改了`zynqmp_dpsub`的`dmas`，分为`vid-layer`和`gfx-layer`，后续没有测试对显示有没有影响，感兴趣可以删除试试看。

```dts
&zynqmp_dpsub {
    vid-layer {
        dma-names = "vid0", "vid1", "vid2";
        dmas = <&zynqmp_dpdma ZYNQMP_DPDMA_VIDEO0>,
            <&zynqmp_dpdma ZYNQMP_DPDMA_VIDEO1>,
            <&zynqmp_dpdma ZYNQMP_DPDMA_VIDEO2>;
    };
    gfx-layer {
        dma-names = "gfx0";
        dmas = <&zynqmp_dpdma ZYNQMP_DPDMA_GRAPHICS>;
    };
};
```

&emsp;&emsp;在解决了硬件电路上接反的问题后，连接显示器后可以正确显示出来。

> [!WARNING]- 警告
> 目前的版本挑显示器，测试的显示器中仅有一台不能正确显示，dp 转 VGA 也可以正常工作。
>
> ```diff
> diff --git a/drivers/gpu/drm/xlnx/zynqmp_dp.c b/drivers/gpu/drm/xlnx/zynqmp_dp.c
> index be63b0e19b60..4a2363c66caf 100644
> --- a/drivers/gpu/drm/xlnx/zynqmp_dp.c
> +++ b/drivers/gpu/drm/xlnx/zynqmp_dp.c
> @@ -958,18 +958,24 @@ static int zynqmp_dp_train(struct zynqmp_dp *dp)
>  	zynqmp_dp_write(dp->iomem, ZYNQMP_DP_TX_PHY_CLOCK_FEEDBACK_SETTING,
>  			reg);
>  	ret = zynqmp_dp_phy_ready(dp);
> -	if (ret < 0)
> +	if (ret < 0) {
> +		dev_err(dp->dev, "DP Phy is not ready\n");
>  		return ret;
> +	}
>
>  	zynqmp_dp_write(dp->iomem, ZYNQMP_DP_TX_SCRAMBLING_DISABLE, 1);
>  	memset(dp->train_set, 0, ARRAY_SIZE(dp->train_set));
>  	ret = zynqmp_dp_link_train_cr(dp);
> -	if (ret)
> +	if (ret) {
> +		dev_err(dp->dev, "clock recovery train is done unsuccessfull\n");
>  		return ret;
> +	}
>
>  	ret = zynqmp_dp_link_train_ce(dp);
> -	if (ret)
> +	if (ret) {
> +		dev_err(dp->dev, "channel equalization train is done unsuccessfull\n");
>  		return ret;
> +	}
>
>  	ret = drm_dp_dpcd_writeb(&dp->aux, DP_TRAINING_PATTERN_SET,
>  				 DP_TRAINING_PATTERN_DISABLE);
> ```
>
> 在驱动中添加了上述调试输出后发现，无法工作的显示器会报`channel equalization train is done unsuccessfull`，目前原因不明，这里具体的报错源头是 aux 通道协商时，返回的信道均衡值不对。

### eMMC 调试

eMMC 很顺利，具体调试过程[参考]({{< ref "posts/emmc-partition/index.zh-cn.md" >}})
