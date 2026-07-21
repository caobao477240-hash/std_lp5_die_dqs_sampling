# std_lp5_die_clk800M

<!-- REVIEW_MOVED_20260718: design review lives in this file -->

LPDDR5 bare-die initialization, RDC training and bank-stream March C- GF test project.

## 当前测试版本说明（2026-07-20）

本工程用于 LPDDR5 裸 die 的 OS、初始化、RDC、IDD6N 和全容量功能测试。
当前速率为 800 MT/s，BL16、RL8、WL6；工程配置文件为
`tools/KU035_DIE_TEST_LP5_20260717.json`。

### 测试流程和时间

```text
板级配置 -> OS -> DIE 上电 -> INIT/RDC -> IDD6N -> GF -> DIE 断电
```

| 测试项 | 测试算法 | FPGA/硬件预计时间 | JSON Timeout |
|--------|----------|-------------------|--------------|
| OS | 先检查各电源对地短路，再逐路加电检查电源间短路 | 正常流程约 1.0 s | 3 s |
| INIT | RESET/CK/CS 上电时序、MR 配置、ZQCAL、读取 MR8 容量 | 约 24.2 ms | 与 RDC 共用 10 s |
| RDC | DQ0～15 并行扫描 tap 0～511，双 pattern 求交集窗口并复验中点 | 通常约 1 ms，边界重试时略增加 | 与 INIT 共用 10 s |
| IDD6N | 预充电、进入自刷新、停止 CK 并保持测量、退出自刷新 | 约 500 ms | 10 s |
| GF | 全容量 6-pass March C-，16 bank 流水访问并按 tREFI 插入刷新 | 见下表 | 60 s |

表中的时间是根据 200 MHz RTL 计数和当前参数计算的算法时间，不包含串口通信、
板级电源切换和上位机软件延时。`Timeout` 只是上位机允许的最长等待时间，不是测试实际耗时。

### RDC 算法

- Pattern0：MR33/MR34 = `5A/A5`；Pattern1：`3C/C3`。
- 16 根 DQ 在同一个 tap 上并行采样，因此不是 16 根 DQ 逐根扫描。
- 两个 pattern 都通过的连续区间才算有效窗口，最小窗口宽度为 4 个采样点。
- 取最长窗口中点，并对两个 pattern 各复验 3 次；复验失败则初始化失败。
- 成功返回 `0xC9`；失败返回 `0x9C`，同时保留 fail mask 和窗口信息。

### GF 算法和时间

GF 使用标准 March C- 顺序：

```text
w0 -> ↑(r0,w1) -> ↑(r1,w0) -> ↓(r0,w1) -> ↓(r1,w0) -> ↑(r0)
```

每个 BL16 地址共执行 5 次写和 5 次读。默认 mode0 使用地址/反地址数据，
并在 burst 内逐 beat 翻转；读比较使用响应 FIFO 中保存的地址和 pattern。

| LPDDR5 容量 | 行数 | March C- 数据流量 | 当前参数预计 GF 时间 |
|-------------|------|--------------------|----------------------|
| 6 Gb | 24,576 | 7.5 GiB | 约 17～18 s |
| 8 Gb | 32,768 | 10 GiB | 约 23～24 s |
| 12 Gb | 49,152 | 15 GiB | 约 34～36 s |
| 16 Gb | 65,536 | 20 GiB | 约 46～48 s |

GF 时间包含当前 ACT/RD/WR/PRE gap `6/12/11/7`、16-bank stream 和 batch=8
刷新造成的预计开销，属于计算值；量产工位时间应以板测日志为准。

## Documentation

- Current configuration: `doc/2026-07-08_LP5调试配置参数说明.md`
- Current open issue: `doc/current_issue.md`
- RDC window policy: `doc/rdc_window_qualification.md`

## Main Tools

- Full board flow: `tools/run_lp5_debug.py`
- RDC tap sweep: `tools/sweep_lp5_rdc_dq_delay.py`
- Board configuration: `tools/KU035_DIE_TEST_LP5_20260717.json`

Generated simulation state, Vivado logs and stale bitstreams are not source artifacts and
should not be committed.

---

# 设计评审

**范围**：架构与实现质量评估  
**目标器件**：Xilinx UltraScale (KU035) + LPDDR5 bare-die 测试  
**评审日期**：2026-07-18

## 1. 工程定位（先对齐评价标准）

这不是通用 LPDDR5 内存控制器，而是 **FPGA 裸 die 测试仪**：

| 能力 | 状态 |
|------|------|
| 上电初始化 + MR 表 | 有 |
| RDC 每 DQ IDELAY 眼扫 / 训练 | 有（双 pattern） |
| March C- GF（bank-stream） | 有 |
| IDD / OS / PMIC / VREF / UART BAR | 有 |
| 多 rank / 多 channel / 随机调度 | 无（也不需要） |

评价应按 **ATE/die-test 质量** 看，而不是按 JEDEC 完整 memory controller 看。

**总评：扎实、经过实硅迭代的实验室级设计；架构分层清楚，工程闭环完整。约 8/10。**

## 2. 架构总览

```
Host (run_lp5_debug.py / JSON)
        │ UART
        ▼
gcs_eft_v1_top
  ├─ clock_manage_top     (40M / 200M / 400M×3 固定相位)
  ├─ BAR00/03/04/05/06/07 (寄存器页)
  └─ lpddr5_dut1
       ├─ lpddr5_gf              (March C- 外层调度)
       ├─ lpddr5_test_scheduler  (INIT / IDD / GF / runtime MR 仲裁)
       │    ├─ lpddr5_init + rdc_train
       │    ├─ lpddr5_idd
       │    └─ lpddr5_gf_engine  (事务级波形)
       └─ lpddr5_channel         (唯一 PHY 边界)
            └─ SERDES + IDELAY + pads
```

核心抽象：

1. **引擎只产生 DH/DL 半 UI 波形**，不直接碰 IO 原语
2. **`lpddr5_channel` 是唯一 PHY 边界**
3. **`test_scheduler` 用 lock 仲裁**，避免 INIT/GF/IDD 抢总线

这是正确的 die-test 分层，也是本工程最大的设计优点。

### Current Architecture（时钟）

- Core clock: 200 MHz
- DQ TX clock: fixed 400 MHz / 0 deg
- CA/WCK clock: fixed 400 MHz / 90 deg
- DQ RX clock: independent fixed 400 MHz / 0 deg
- Dynamic RX phase control is removed
- GF supports bank-stream scheduling and selectable address-toggle/beat-ramp patterns


