---
title: 'PCIe MMIO 写入与内存屏障'
date: 2026-11-24T17:07:00+08:00
lastmod: 2026-11-25T15:45:00+08:00
draft: true
description: 'PCIe MMIO 写入与内存屏障'
images: []
tags: ['pcie', 'linux', 'mmio']
categories: ['嵌入式系统']
---

**PCIe MMIO** 的写入顺序及完成状态。

<!--more-->

## SFENCE 能保证什么

假设设备提供 DATA 和 START 两个寄存器，软件先写 DATA，再写 START。对于 WC 映射，下面的两段代码是否等价？

```c
*data = value;
*start = 1;
```

```c
*data = value;
_mm_sfence();
*start = 1;
```

两段代码在 C 语言层面的访问顺序相同（假设指针均具有 volatile 限定），但 WC 允许处理器合并和重新安排写入。第二段增加了处理器层面的 store ordering 约束。

> 参考 [Intel SDM](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)，Volume 3 的 Memory Cache Control、Memory Ordering 章节，以及 Volume 2 的 SFENCE、MOVNTI 指令说明。

这里需要区分三个位置。

```goat
 .--------.     .--------.     .--------.     .--------.
 | CPU    |---->| RC     |---->| PCIe   |---->| Device |
 | WC buf |     |        |     | EP     |     | Logic  |
 '--------'     '--------'     '--------'     '--------'
```

SFENCE 约束前后的 store，并不要求设备逻辑返回确认。即使 CPU 已经完成 fence，Posted Write 仍可能处于下游缓冲中。

### MOVNTI

普通 store 写入 WC 类型地址时，本身就适用 WC 的内存类型规则，并非必须使用 MOVNTI 才能合并写入。MOVNTI 提供 non-temporal store hint；对于 WC 地址，不能因为使用了 MOVNTI 就认为每条指令对应一个独立 TLP。

下面使用两个独立函数观察编译器生成的指令。

```c
#include <stdint.h>
#include <emmintrin.h>

void store(volatile uint32_t *p, uint32_t v)
{
    *p = v;
    _mm_sfence();
}

void nt_store(uint32_t *p, uint32_t v)
{
    _mm_stream_si32((int *)p, (int)v);
    _mm_sfence();
}
```

```bash
gcc -O2 -S -masm=intel store.c -o store.s
```

查看 store.s 中的 mov、movnti 和 sfence 即可。此处只能验证编译结果，不能通过汇编判断 RC 发出的 TLP 数量。

WC buffer 可能在写满、执行相关 fence 或其他处理器内部条件下排出。写入未填满整个合并单元也可能被发送。Intel SDM 并没有提供可供软件依赖的逐 TLP 分包算法。

## Linux 中的 barrier

> 参考 [Linux memory barriers](https://docs.kernel.org/core-api/wrappers/memory-barriers.html)、[Device I/O](https://docs.kernel.org/driver-api/device-io.html)。

| 接口 | 使用场景 |
| --- | --- |
| barrier() | 限制编译器重排，不直接约束硬件 |
| smp_wmb() | CPU 之间的共享内存 store ordering |
| wmb() | 包括设备访问在内的 mandatory write barrier |
| io_stop_wc() | 避免前后的 WC 访问被合并 |
| mmiowb() | 处理架构相关的跨 CPU MMIO 写入排序问题 |

其中 io_stop_wc() 不是通用的 posted write flush。mmiowb() 也不表示设备返回了完成确认。

可以对照 [arch/x86/include/asm/barrier.h](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/asm/barrier.h) 和 [include/asm-generic/barrier.h](https://github.com/torvalds/linux/blob/v6.12/include/asm-generic/barrier.h)。不要将某一架构上的空实现或指令实现直接推广到其他架构。

### 内核中的写入示例

假设设备将允许合并的数据空间和控制寄存器分别映射，并且设备协议规定先接收数据再启动。

```c
memcpy_toio(data, buf, len);
wmb();
writel(1, ctrl + REG_START);
```

上面解决的是发布顺序。若要求确认 posted write 已经到达设备，还需要一个满足 ordering 条件、可以安全读取的寄存器。

```c
readl(ctrl + REG_STATUS);
```

如果设备将数据和控制请求交给两个独立的内部队列，那么即使 PCIe 接口按顺序收到请求，内部处理仍可能出现先后差异。此时需要由设备协议定义何时允许执行 START。

## PCIe Transaction Ordering

MWr 属于 Posted Request，没有 Transaction Layer Completion。Data Link Layer ACK 不能代替该 Completion。

在 PCIe Base Specification 的 Transaction Ordering 表中，普通 Posted Request 不应越过同一 ordering domain 内先前的 Posted Request。Relaxed Ordering、ID-Based Ordering 以及不同 Traffic Class 等条件需要分别考虑。

因此不能用“PCIe MWr 可以乱序”解释所有现象。首先要确认顺序在哪一级被改变。

### 如何确认写入到达

Linux 的 Device I/O 文档中通过读取同一设备的寄存器处理 posted write。该 readback 必须满足相应 PCIe ordering 条件。

若 CPU 使用 WC 映射写数据，再进行 MMIO readback，应先完成相应的 WC store 排序，不能把任意普通内存读取当作 flush。

另外，readback 所能证明的是相应的 PCIe 写入已被排到读取之前，并不自动证明设备内部异步任务结束。对于异步任务，应该读取由该任务更新的完成状态。

## 验证

可以使用独立的测试 Endpoint，只提供一段允许任意写入的测试空间和一个无读取副作用的状态寄存器。不要使用已有设备的实际控制寄存器。

在 PCIe RX 接口处记录每个 MWr 的地址、Length、First/Last DW BE 和接收序号，在设备处理逻辑之后另外记录提交序号。如果使用 AXI 接口而非原始 TLP 接口，只能观察 IP 转换后的事务，不能反推出准确的原始 TLP。

对同一组写入分别执行：

| 测试 | 需要观察的内容 |
| --- | --- |
| UC 普通 store | 地址、byte enable 和顺序 |
| WC 普通 store | 合并、拆分及部分写入 |
| WC MOVNTI | 与普通 store 的差异 |
| WC + SFENCE | fence 前后的请求顺序 |
| WC + SFENCE + readback | 读取与先前写入的关系 |

每组测试改变起始地址对齐、写入间隔及是否跨越合并单元，记录原始事务而不是仅记录最终寄存器值。最终值相同并不能证明事务顺序相同。

以上为测试方法，未提供实测结果。对于没有观察到的乱序，也不能据此证明硬件在所有条件下都不会乱序。
