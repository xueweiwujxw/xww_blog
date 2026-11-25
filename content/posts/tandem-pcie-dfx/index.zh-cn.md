---
title: 'Xilinx Tandem PCIe 与 DFX'
date: 2026-11-24T17:07:00+08:00
lastmod: 2026-11-25T15:45:00+08:00
draft: true
description: 'Xilinx Tandem PCIe 与 DFX'
images: []
tags: ['xilinx', 'vivado', 'pcie', 'dfx']
categories: ['FPGA']
---

**Vivado DCP** 中的物理实现及 DFX 中 static 的保留。

<!--more-->

## 为什么 Synth DCP 不能固定物理实现

将一个已经综合的模块通过 read_checkpoint 读入另一个工程，只能保证读入的是该模块的综合结果。对于未固定的逻辑，place_design 和 route_design 仍然需要决定其物理位置和路径。

要保留的是 placement 和 routing，而不仅仅是 netlist。

> 参考 [UG909 - Preserving Implementation Data](https://docs.amd.com/r/en-US/ug909-vivado-partial-reconfiguration/Preserving-Implementation-Data)。

## 查看 DCP 中的信息

对于普通逻辑单元，LOC 表示 site，BEL 表示 site 内部的具体资源。对于 net，ROUTE 描述其布线路径。已分配位置与位置被固定是两回事。

打开一个 routed checkpoint，查看指定实例。

```tcl
open_checkpoint config_a_routed.dcp
report_property [get_cells u_static/q_reg]
report_property [get_nets u_static/q]
```

实际名称需要根据综合网表调整。重点关注以下属性。

| 属性 | 用途 |
| --- | --- |
| LOC / BEL | cell 的位置 |
| IS_LOC_FIXED / IS_BEL_FIXED | cell 位置的固定状态 |
| ROUTE | net 的路由信息 |
| FIXED_ROUTE / IS_ROUTE_FIXED | 固定路由信息及状态 |

> 参考 [UG912 - Vivado Properties Reference](https://docs.amd.com/r/en-US/ug912-vivado-properties)。

不能只比较 LOC：同一个 site 中仍有不同 BEL，也可能存在相同 placement 而 routing 不同的情况。

## DFX 最小设计

下面使用一个与具体 IP 无关的设计说明流程。Static 中包含输入输出寄存器，RP 中只放组合逻辑，两个 RM 使用相同接口。

```verilog
module top(
    input  wire clk,
    input  wire a,
    input  wire b,
    output reg  q
);
    reg x, y;
    wire z;

    always @(posedge clk) begin
        x <= a;
        y <= b;
        q <= z;
    end

    op u_rp (.a(x), .b(y), .z(z));
endmodule
```

RM_A：

```verilog
module op(input wire a, b, output wire z);
    assign z = a ^ b;
endmodule
```

RM_B：

```verilog
module op(input wire a, b, output wire z);
    assign z = a & b;
endmodule
```

两个 op 分别进行 OOC synthesis，不要同时读入两个同名模块。top 综合时将 op 定义为 black box。器件、时钟、IO 和 Pblock 根据实验板卡配置；这里不提供绑定到某个实际器件的约束。

在已链接 RM_A 的设计中设置 RP，并添加实际合法的 Pblock。

```tcl
set_property HD.RECONFIGURABLE true [get_cells u_rp]
create_pblock pblock_rp
add_cells_to_pblock [get_pblocks pblock_rp] [get_cells u_rp]
# resize_pblock 使用实际器件上合法的 SLICE 范围
```

完成 DFX DRC、place、route 和时序检查后，将初始 configuration 保存为 config_a_routed.dcp。

## 提取 Static

```tcl
open_checkpoint config_a_routed.dcp
update_design -cell u_rp -black_box
lock_design -level routing
write_checkpoint -force static_routed.dcp
```

update_design 移除的是 RP 内的逻辑实现，并不删除 RP 对应的层级接口。lock_design 用来保留剩余设计的物理实现。

这里只针对 DFX 流程，不建议通过逐个设置 IS_LOC_FIXED 的方式代替该步骤，因为跨边界 net 和 routing 也需要处理。

### 比较物理实现

对于完全位于 static 中的普通逻辑，可以导出 cell 和 net 的属性，比较不同 checkpoint。

```tcl
proc dump_phys {path cells nets} {
    set fd [open $path w]
    foreach c [lsort $cells] {
        puts $fd [list CELL $c [get_property LOC $c] \
                             [get_property BEL $c]]
    }
    foreach n [lsort $nets] {
        puts $fd [list NET $n [get_property ROUTE $n]]
    }
    close $fd
}
```

调用时显式传入确认属于 static 的 cell 和 net，不要将整个设计的 net 都拿来比较。跨 RP 接口的 net 包含可以改变的 RM 侧路径，不能将完整 ROUTE 当作 static 是否变化的判断依据。

使用相同的对象清单分别在初始 configuration 和后续 configuration 中导出，然后通过 diff 查看。这个方法只能辅助定位问题，不能代替 pr_verify。

## 插入 RM_B

```tcl
open_checkpoint static_routed.dcp
read_checkpoint -cell u_rp rm_b_synth.dcp
opt_design
place_design
route_design
write_checkpoint -force config_b_routed.dcp

pr_verify -full_check config_a_routed.dcp config_b_routed.dcp
```

pr_verify 用于检查 DFX configuration 的兼容性，不是 timing signoff。两个 configuration 都需要独立检查时序。

### 为什么 Static 已经收敛，仍然需要检查时序

假设路径由 static 中的寄存器发出，在 RP 内经过组合逻辑，最后到达 static 中的寄存器。

```goat
 .----.        .------------.        .----.
 | FF |------->| RM logic   |------->| FF |
 '----'        '------------'        '----'
 static             RP               static
```

两个端点的 placement 可以相同，static 侧路由也可以保留，但 RM 的逻辑和路由不同，整个路径的 delay 就可能改变。

Partition Pin 是边界路由的连接位置，并不等于在这里自动插入一个寄存器。如果 RP 接口有大量组合路径，固定外部设计后，后续 RM 的时序优化空间会受到限制。

> 参考 [UG909 - Register Inputs and Outputs of RMs](https://docs.amd.com/r/en-US/ug909-vivado-partial-reconfiguration/Register-Inputs-and-Outputs-of-RMs)。

## Abstract Shell 和 Nested DFX

Abstract Shell 不是将 static 的所有 cell 简单删除。它保留当前 RP 实现需要的物理资源限制、接口连接和时序上下文，减少无关逻辑。

Nested DFX 则允许在 Parent RP 内继续定义 Child RP。相对于 Child RP，Parent RM 中不属于 Child RP 的部分可以保留；相对于 Parent RP，这些逻辑仍然属于可更新范围。

两者分别解决设计数据库和更新粒度的问题，不是同一个功能。

## Tandem PCIe

Tandem Stage 1 / Stage 2 是初始配置顺序，DFX Static / RP 是运行时可重配置边界。不能根据前者直接推导后者的范围。

对于 Tandem PCIe with Field Updates，需要根据 PCIe IP 对应的官方流程确定初始配置文件及后续 partial bitstream。普通 DFX 的 DCP 提取流程并不能证明某种 Tandem、Nested DFX、Abstract Shell 组合一定受支持。

> 参考 [PG213](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus) 和 [UG909](https://docs.amd.com/r/en-US/ug909-vivado-partial-reconfiguration)。

上述最小设计用于验证物理实现的保留方法，未进行实际 Vivado implementation，不包含板卡相关的 Pblock、XDC 或时序结果。
