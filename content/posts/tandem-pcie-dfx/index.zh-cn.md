---
title: 'Xilinx Tandem PCIe 与 DFX'
date: 2026-11-24T17:07:00+08:00
lastmod: 2026-11-24T17:07:00+08:00
draft: true
description: 'Xilinx Tandem PCIe 与 DFX'
images: []
tags: ['xilinx', 'vivado', 'pcie', 'dfx']
categories: ['FPGA']
---

**Tandem PCIe** 与 **DFX** 的配置流程。

<!--more-->

## Tandem Configuration

FPGA 作为 PCIe Endpoint 时，需要在主机枚举 PCIe 设备之前完成 PCIe 相关逻辑的配置。Tandem Configuration 将初始配置分为 Stage 1 和 Stage 2。

> 参考 [UG909 - Tandem Configuration and PCIe](https://docs.amd.com/r/2024.2-English/ug909-vivado-partial-reconfiguration/Tandem-Configuration-and-PCIe)。下面主要讨论 UltraScale+，其他器件需要参考对应的 IP 文档。

### Tandem PROM

Stage 1 和 Stage 2 均通过配置存储器加载。Stage 1 配置完成后，PCIe 相关逻辑可以开始建立 Link，剩余逻辑通过 Stage 2 完成配置。

### Tandem PCIe

Stage 1 通过配置存储器加载，Stage 2 通过 PCIe 加载。对于支持该模式的 PCIe IP，可以通过 MCAP (Media Configuration Access Port) 传输配置数据。

```goat
 .-------.         .---------.
 | Flash |-------->| Stage 1 |
 '-------'         '----+----'
                        |
                    PCIe Link
                        |
 .-------.         .----v----.
 | Host  |-------->| Stage 2 |
 '-------'  PCIe   '---------'
```

普通 Tandem PCIe 的 Stage 2 用于完成初始配置，不能直接将其当作运行过程中可反复加载的 partial bitstream。

## DFX

DFX (Dynamic Function eXchange) 将设计划分为 Static Region 和可重配置的区域。

- RP (Reconfigurable Partition)：可重配置的层级。
- RM (Reconfigurable Module)：RP 对应的具体逻辑实现。
- Pblock：用于约束 RP 对应的物理资源范围。

```goat
 .--------------------------------.
 | Static                         |
 |    .----------------------.    |
 |    | RP                   |    |
 |    | RM_A / RM_B          |    |
 |    '----------------------'    |
 '--------------------------------'
```

RM_A 和 RM_B 是同一个 RP 的不同实现，需要满足对应的接口约束。通过 partial bitstream 可以替换 RP 内部的 RM，而不重新配置 Static Region。

### DCP

Synth DCP 包含综合后的设计信息，后续还需要进行 place 和 route。Routed DCP 则包含已经完成布线的设计信息。

对于 DFX，可以将初始 configuration 中的 RM 移除，并保留 Static Region 的物理实现。

```tcl
open_checkpoint config_a_routed.dcp
update_design -cell u_rp -black_box
lock_design -level routing
write_checkpoint -force static_routed.dcp
```

后续可以读入新的 RM。

```tcl
open_checkpoint static_routed.dcp
read_checkpoint -cell u_rp rm_b_synth.dcp
opt_design
place_design
route_design
write_checkpoint -force config_b_routed.dcp
```

上面的命令只用于说明 DCP 的处理过程，RP、Pblock 和相关约束需要提前配置。生成 bitstream 前还需要检查时序和不同 configuration 的兼容性。

```tcl
pr_verify -full_check config_a_routed.dcp config_b_routed.dcp
```

> 参考 [UG909 - Dynamic Function eXchange](https://docs.amd.com/r/2024.2-English/ug909-vivado-partial-reconfiguration)。

## Tandem PCIe with Field Updates

Tandem 解决初始配置问题，DFX 解决运行过程中的逻辑更新问题。支持 Field Updates 的模式将两者结合。

```goat
 .---------.
 | Stage 1 |
 '----+----'
      |
      v
 .---------.
 | Stage 2 |
 '----+----'
      |
      v
 .--------------.     .-------------------.
 | Initial RM   |<----| Partial Bitstream |
 '--------------'     '-------------------'
```

需要区分 Stage 2 bitstream 和后续用于更新 RP 的 partial bitstream。Stage 1、Stage 2 是配置阶段的划分，并不完全等价于 Static 和 RP 的划分。

> 参考 [PG213 - UltraScale+ Devices Integrated Block for PCI Express](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus)。

## Nested DFX

Nested DFX 允许在 RP 内继续划分下一级 RP。

```goat
 .--------------------------------.
 | Static                         |
 | .----------------------------. |
 | | Parent RP                  | |
 | |   Parent Logic             | |
 | |   .--------------------.   | |
 | |   | Child RP           |   | |
 | |   '--------------------'   | |
 | '----------------------------' |
 '--------------------------------'
```

更新 Child RP 时，可以保留当前 Parent RM 中的其他逻辑。更新 Parent RP 时，内部的 Child RP 也属于被重新配置的范围。

Abstract Shell 则是面向特定 RP 的设计检查点，用于保留 RM 实现所需的物理和时序上下文，两者不是同一个概念。

> [!NOTE]
>
> Nested DFX、Abstract Shell 和 Tandem 的组合支持情况需要根据器件、PCIe IP 和 Vivado 版本确认，不能仅根据各个功能分别受支持就认为组合方式可用。
