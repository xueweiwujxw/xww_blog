---
title: 'PCIe MMIO 写入与内存屏障'
date: 2026-11-24T17:07:00+08:00
lastmod: 2026-11-24T17:07:00+08:00
draft: true
description: 'PCIe MMIO 写入与内存屏障'
images: []
tags: ['pcie', 'linux', 'mmio']
categories: ['嵌入式系统']
---

**PCIe MMIO** 写入顺序及 posted write 的确认。

<!--more-->

## BAR 映射

PCIe 设备通过 BAR 提供 MMIO 地址空间。对于 x86，主要关注 UC (Uncacheable) 和 WC (Write Combining) 两种映射方式。

> 参考 [Linux Device Memory Mapping Modes](https://docs.kernel.org/driver-api/device-io.html#device-memory-mapping-modes) 和 [Intel SDM](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)。

- UC：用于普通设备寄存器，不进行 WC 写合并。
- WC：允许合并写操作，适用于允许合并、拆分和推测读取的数据空间。

WC 写入的合并方式取决于处理器和地址等条件，不能通过 C 代码中的 store 次数确定 PCIe TLP 的数量和长度。

### kernel space

假设 BAR0 为控制空间，BAR2 为支持 prefetchable 的数据空间，可以分别使用下面的接口映射。

```c
void __iomem *ctrl = pci_iomap(pdev, 0, 0);
void __iomem *data = pci_iomap_wc(pdev, 2, 0);
```

控制寄存器使用 `readl()` 和 `writel()` 访问。实际驱动需要检查映射结果，并在释放资源时调用 `pci_iounmap()`。

### user space

> 参考 [Accessing PCI device resources through sysfs](https://docs.kernel.org/PCI/sysfs-pci.html)。

通过 sysfs 可以查看 BAR 对应的 resource 文件。

```bash
ls /sys/bus/pci/devices/<BDF>/resource*
```

对于支持 WC 映射的资源，可能存在 `resourceN_wc` 文件。通过 `mmap()` 映射对应的文件即可。

```c
int fd = open(path, O_RDWR);
void *bar = mmap(NULL, size, PROT_READ | PROT_WRITE,
                 MAP_SHARED, fd, 0);
```

其中 path 为对应的 resource 文件，size 不应超过资源范围。这里省略了错误处理和资源释放，不要在其他驱动使用该地址空间时直接访问 BAR。

## Posted Write

PCIe Memory Write 是 Posted Request，不需要 Transaction Layer 返回 Completion；Memory Read 是 Non-Posted Request，需要返回 Completion。

```goat
Host                       Endpoint
  |                            |
  |---------- MWr ------------>|
  |                            |
  |---------- MRd ------------>|
  |<--------- CplD ------------|
  |                            |
```

这里需要区分 Transaction Layer 的 Completion 和 Data Link Layer 的 ACK。MWr 不返回 Completion，并不意味着链路层没有重传机制。

## 写入顺序

### CPU

假设通过 WC 映射写入两个不同的地址，在两次写入之间添加 `sfence`。

```c
#include <immintrin.h>

void write_regs(volatile uint32_t *bar)
{
    bar[0] = 1;
    _mm_sfence();
    bar[1] = 2;
}
```

`sfence` 用于保证前后的 store 满足 x86 的 store ordering 要求。这里的 `volatile` 不能替代 `sfence`。

> [!NOTE]
>
> `sfence` 不是 PCIe 的 Completion，执行结束不能说明 Endpoint 内部逻辑已经处理了对应的写操作。

### PCIe

PCIe Transaction Layer 本身也存在 ordering rules。在相同 ordering domain 内，且未通过 Relaxed Ordering、ID-Based Ordering 等机制放宽相关约束的情况下，后续 Posted Request 不能随意越过前面的 Posted Request。

CPU 的 store 顺序、PCIe TLP 的顺序以及 Endpoint 内部逻辑的处理顺序需要分别考虑。

### Readback

如果需要 flush PCIe posted write，可以读取同一设备中允许安全读取的寄存器。

```c
writel(value, ctrl + REG_CTRL);
readl(ctrl + REG_STATUS);
```

对于 user space 的 WC 写入，需要先对之前的 store 进行排序，再通过合适的 MMIO readback 完成 flush。Readback 需要满足 PCIe ordering 条件。

如果 REG_CTRL 用于启动某个异步操作，那么 readback 并不能代替该操作本身的完成状态，仍然需要通过设备定义的状态寄存器判断。

> 参考 [Linux Bus-Independent Device Accesses](https://docs.kernel.org/driver-api/device-io.html) 中关于 posted writes 和 access ordering 的描述。
