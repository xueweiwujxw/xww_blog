---
title: 'PTP 与 PCIe PTM 时间同步'
date: 2026-11-24T17:07:00+08:00
lastmod: 2026-11-25T15:45:00+08:00
draft: true
description: 'PTP 与 PCIe PTM 时间同步'
images: []
tags: ['ptp', 'ptm', 'pcie', 'linux']
categories: ['嵌入式系统']
---

**Linux PHC** 与系统时钟之间的时间关联。

<!--more-->

## 从 clock_gettime 开始

PHC 可以通过 /dev/ptpN 访问，Linux 将其作为 dynamic clock 暴露给用户态。

```c
#include <fcntl.h>
#include <time.h>
#include <unistd.h>

#define FD_TO_CLOCKID(fd) ((clockid_t)((~(clockid_t)(fd) << 3) | 3))

/* 示例：fd 为已经成功打开的 PHC 字符设备 */
struct timespec ts;
clock_gettime(FD_TO_CLOCKID(fd), &ts);
```

这里读取的是 PHC，而不是系统的 CLOCK_REALTIME。若分别调用两次 clock_gettime，两个返回值对应的采样时刻不同，不能直接相减当作同一时刻的 offset。

## PTP_SYS_OFFSET_EXTENDED

Linux 提供了专门用于比较 PHC 和系统时钟的 ioctl。

> 参考 Linux v6.12 的 [include/uapi/linux/ptp_clock.h](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/ptp_clock.h)、[drivers/ptp/ptp_chardev.c](https://github.com/torvalds/linux/blob/v6.12/drivers/ptp/ptp_chardev.c) 和 [include/linux/ptp_clock_kernel.h](https://github.com/torvalds/linux/blob/v6.12/include/linux/ptp_clock_kernel.h)。

PTP_SYS_OFFSET_EXTENDED 返回多组由三个时间戳组成的采样。

```goat
 System          PHC          System
   s0             p              s1
   |--------------+--------------|
```

驱动的 gettimex64 可以利用 ptp_read_system_prets 和 ptp_read_system_postts 将系统时间的采样放在实际读取硬件时钟的位置附近，而不是由用户态在 ioctl 前后打点。

### offset 的计算

假设测量期间两个时钟的速率相同，PHC 时间减去系统时间为 offset，并且 p 对应的实际系统时刻 s 落在 [s0, s1] 内。

```
offset = p - s

p - s1 <= offset <= p - s0
```

如果没有其他信息，可以使用区间中点。

```
s_est = (s0 + s1) / 2
offset_est = p - s_est
error_bound = (s1 - s0) / 2
```

这个误差范围的前提是硬件采样确实发生在区间内，且系统时间在此期间没有 step。若设备返回的是提前缓存的时间，或者 pre/post 打点没有包住实际 latch，则上述结论不成立。

这也是 gettimex64 实现需要注意的地方：不能将任意一次寄存器读取的时刻当作计数器的采样时刻。

### 采样程序

下面的程序读取 EXTENDED ioctl 返回的原始结果，输出 CSV。使用整数计算纳秒，避免先将绝对时间转换成 double。

```c
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/ptp_clock.h>

static int64_t ns(struct ptp_clock_time t)
{
    return t.sec * INT64_C(1000000000) + t.nsec;
}

int main(int argc, char **argv)
{
    if (argc != 3)
        return 1;

    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    int groups = atoi(argv[2]);
    puts("group,s0,p,s1");
    for (int g = 0; g < groups; g++) {
        struct ptp_sys_offset_extended e = {0};
        e.n_samples = PTP_MAX_SAMPLES;
        if (ioctl(fd, PTP_SYS_OFFSET_EXTENDED, &e) < 0) {
            perror("PTP_SYS_OFFSET_EXTENDED");
            close(fd);
            return 1;
        }
        for (unsigned i = 0; i < e.n_samples; i++)
            printf("%d,%lld,%lld,%lld\n", g,
                (long long)ns(e.ts[i][0]),
                (long long)ns(e.ts[i][1]),
                (long long)ns(e.ts[i][2]));
        sleep(1);
    }
    close(fd);
    return 0;
}
```

```bash
gcc -O2 -Wall sample.c -o sample
./sample /dev/ptp0 10 > samples.csv
```

设备需要支持对应 ioctl；不支持时不能用虚构的 pre/post 时间补齐。

## 频率偏移的计算

对于连续采样，可以用线性模型描述两个时钟之间的关系。

```
PHC(t) = a * SYS(t) + b
```

其中 a 是相对速率，a - 1 是相对频率偏移，b 取决于两个时钟的时间原点。

由于绝对时间数值比较大，拟合时先减去第一组采样的系统时间和 PHC 时间。下面的代码在每组采样中选择 pre/post 区间最短的记录，然后进行线性回归。

```python
import csv
from collections import defaultdict
from statistics import mean

groups = defaultdict(list)
with open("samples.csv") as f:
    for r in csv.DictReader(f):
        g, s0, p, s1 = (
            int(r[k]) for k in ("group", "s0", "p", "s1")
        )
        if s1 >= s0:
            groups[g].append((s1 - s0, s0 + (s1-s0)//2, p))

samples = [min(v) for _, v in sorted(groups.items()) if v]
if len(samples) < 2:
    raise ValueError("not enough samples")

_, s_ref, p_ref = samples[0]
x = [s - s_ref for _, s, p in samples]
# 拟合 offset 的变化而不是直接拟合绝对时间
y = [(p - p_ref) - (s - s_ref) for _, s, p in samples]

xm, ym = mean(x), mean(y)
den = sum((v - xm)**2 for v in x)
if not den:
    raise ValueError("zero observation interval")
k = sum((u-xm)*(v-ym) for u,v in zip(x,y)) / den
print("relative frequency offset (ppb):", k * 1e9)
```

最短区间筛选主要减少可变读取延迟带来的不确定性，不能消除固定的读请求和响应路径非对称。如果这种非对称随时间变化，频率估计也会受到影响。

另外，EXTENDED 默认使用系统实时时钟。如果系统时间发生 step，或者系统和 PHC 正在被其他 servo 调频，不能将整段采样当作同一个恒定频率模型。该程序只适用于没有时间跳变、速率近似稳定的观测区间。

## PTP_SYS_OFFSET_PRECISE

PRECISE 和 EXTENDED 并不是同一种采样方式。PRECISE 通过驱动的 getcrosststamp 获得设备时间和与其关联的系统时间。

返回结构中包含 device、sys_realtime 和 sys_monoraw。驱动需要提供真实的 cross timestamp 能力；仅通过顺序读取两个时钟不能获得同等保证。

> 参考 [kernel/time/timekeeping.c](https://github.com/torvalds/linux/blob/v6.12/kernel/time/timekeeping.c) 中的 get_device_system_crosststamp，以及上述 ptp_chardev.c。

该接口的作用是提供时间关联，不会自动改变 PHC 的运行频率。

## PCIe PTM

PTM 提供 PCIe 组件本地时间与 PTM Master Time 的关联。它需要拓扑中的相应组件支持并启用 PTM。

```bash
sudo lspci -vv
```

查看 PTM capability 和控制状态。Linux 对 PTM capability 的处理可以参考 [drivers/pci/pcie/ptm.c](https://github.com/torvalds/linux/blob/v6.12/drivers/pci/pcie/ptm.c)。

需要注意，该文件主要处理 PTM 的发现及启用，并不是通用的 PTM 时间读取接口。Endpoint 是否能够将 PTM 测量结果交给驱动，需要看设备本身的实现。

即使可以取得 PTM Master Time，还需要知道它与系统所用时间域之间的关系。

```goat
 .--------------.     .-----------------.     .--------------.
 | Device Clock |---->| PTM Master Time |---->| System Clock |
 '--------------'     '-----------------'     '--------------'
```

假设这两段关系分别为 M = aD + b 和 S = cM + d，那么最终 S = caD + cb + d。只知道第一段关系无法得到系统时间。

PTP 可以作为外部授时来源，PTM 可以作为 PCIe 内部时间关联的来源。它们都不能代替系统中实际需要的时钟转换和控制算法。

本文的采样程序和拟合方法不包含实际硬件测量结果。
