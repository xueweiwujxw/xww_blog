---
title: 'PTP 与 PCIe PTM 时间同步'
date: 2026-11-24T17:07:00+08:00
lastmod: 2026-11-24T17:07:00+08:00
draft: true
description: 'PTP 与 PCIe PTM 时间同步'
images: []
tags: ['ptp', 'ptm', 'pcie', 'linux']
categories: ['嵌入式系统']
---

**PTP** 和 **PCIe PTM** 中的时间测量及 Linux PHC。

<!--more-->

## Clock

两个独立时钟之间需要考虑时间偏移 (phase offset) 和频率偏移 (frequency offset)。假设两个时钟的频率分别为 f1 和 f2，相对频率偏移可以表示为 (f2 - f1) / f1。

只调整频率，可以减小时间差随时间的变化，但不能直接消除已经存在的时间偏移。

## PTP

PTP (Precision Time Protocol) 由 IEEE 1588 定义，下面主要关注 E2E 的 two-step 模式。

### Message

- Sync：发送同步消息。
- Follow_Up：携带 Sync 对应的发送时间。
- Delay_Req：发送延迟测量消息。
- Delay_Resp：返回 Delay_Req 对应的接收时间。

```goat
 Server                         Client
   |                               |
 t1|----------- Sync ------------->|t2
   |--------- Follow_Up ---------->|
   |                               |
 t4|<-------- Delay_Req -----------|t3
   |--------- Delay_Resp --------->|
   |                               |
```

假设 Client 相对于 Server 的时间偏移为 offset，两个方向的链路延迟均为 d，暂时忽略 correctionField 和测量期间的频率偏移。

```
t2 - t1 = d + offset
t4 - t3 = d - offset

d      = ((t2 - t1) + (t4 - t3)) / 2
offset = ((t2 - t1) - (t4 - t3)) / 2
```

如果两个方向的实际延迟不相等，那么计算得到的 offset 中也会包含链路非对称引入的误差。

### Hardware Timestamp

如果在应用程序中记录数据包的接收时间，时间戳中包含了设备、驱动、协议栈等环节的延迟。硬件打点可以减少软件处理对测量的影响。

硬件打点也需要明确对应的参考位置，例如 MAC 或 PHY 内部接口。发送和接收的打点位置不同，需要考虑相应的固定延迟。

## Linux PHC

> 参考 [PTP hardware clock infrastructure for Linux](https://docs.kernel.org/driver-api/ptp.html)。

PHC (PTP Hardware Clock) 是 Linux 提供的硬件时钟接口。可以通过下面的命令查看设备。

```bash
ls /dev/ptp*
ethtool -T eth0
ls /sys/class/net/eth0/device/ptp/
```

`ethtool -T` 输出中的 PTP Hardware Clock 为对应 PHC 的序号。实际支持的时间读取、频率调整、外部事件等功能由驱动实现。

### ptp4l

以支持 hardware timestamp 的网卡为例，安装 linuxptp 后可以通过下面的命令启动 client。

```bash
sudo ptp4l -i eth0 -H -s -m
```

这里假设网络使用默认的 PTP transport 和 delay mechanism，实际需要根据上游 PTP 配置调整。

### phc2sys

PHC 和 Linux System Clock 是两个独立的时钟。ptp4l 同步 PHC 后，可以通过 phc2sys 同步系统时间。

```bash
sudo phc2sys -s eth0 -c CLOCK_REALTIME -w -m
```

```goat
 .------------.
 | PTP Server |
 '-----+------'
       |
    Ethernet
       |
 .-----v------.
 |  NIC PHC   |
 '-----+------'
       |
    phc2sys
       |
 .-----v------.
 | System     |
 | Clock      |
 '------------'
```

`-w` 等待 ptp4l 进入相应的工作状态，并从 ptp4l 获取 UTC offset 等信息。需要避免多个时间同步服务同时调整 System Clock。

> 参考 [ptp4l](https://www.linuxptp.org/documentation/ptp4l/) 和 [phc2sys](https://www.linuxptp.org/documentation/phc2sys/)。

## PCIe PTM

PTM (Precision Time Measurement) 用于建立 PCIe 组件本地时间与 PTM Master Time 之间的关系。

### Capability

可以通过 lspci 查看设备的 PTM Extended Capability。

```bash
sudo lspci -vv -s <BDF>
```

主要关注下面几个字段。

- Requester：支持发起 PTM 测量。
- Responder：支持响应 PTM 测量。
- Root：具备作为 PTM Root 的能力。
- Enabled：PTM 是否启用。
- RootSelected：是否被选为 PTM Root。

设备具有 PTM Capability 并不代表已经启用 PTM，还需要检查上游 PCIe 组件的支持情况。

> Linux 中 PTM 的配置过程可以参考 [drivers/pci/pcie/ptm.c](https://github.com/torvalds/linux/blob/master/drivers/pci/pcie/ptm.c)。

### 时间测量

下面是简化后的双向时间测量关系，并不是完整的 PTM Message 时序。

```goat
 Requester                  Responder
     |                          |
   t1|-------- Request -------->|t2
   t4|<------- Response --------|t3
     |                          |
```

假设两个方向延迟相同，且测量期间频率偏差可以忽略，可以从往返时间中减去 Responder 内部的处理时间，得到单向延迟的估计值。

```
d = ((t4 - t1) - (t3 - t2)) / 2
```

实际 PTM 涉及 PTM Request、PTM Response 和 PTM ResponseD，时间信息的传递需要按照 PCIe Base Specification 处理。

### PTM Master Time

PTM Master Time 不一定等于 Linux 的 CLOCK_REALTIME，也不一定等于 TSC。如果需要通过 PTM 将设备时间关联到系统时间，还需要处理 PTM Master Time 与系统时钟之间的关系。

```goat
 .------------------.
 | System Clock     |
 '--------+---------'
          |
    Clock Correlation
          |
 .--------v---------.
 | PTM Master Time  |
 '--------+---------'
          |
         PTM
          |
 .--------v---------.
 | Endpoint Clock   |
 '------------------'
```

PTP 用于网络时钟同步，PTM 用于 PCIe 拓扑内的时间测量。两者所使用的时间域需要分别处理。
