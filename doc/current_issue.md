# LPDDR5 当前问题

更新时间：2026-07-15

## 当前基线

- RX ISERDES 使用独立 `400 MHz / 0 deg` 固定时钟。
- Clock Wizard 动态调相已关闭，BAR06 `0x0614` 和上位机相位参数已删除。
- ISERDES 不使用内部 FIFO，不在运行过程中复位；只受系统 `rst_n` 控制。
- 原有读采集窗口、写 payload 窗口、beat offset 和每 DQ IDELAY 训练接口保持不变。
- GF 默认 mode 0 为地址/反地址逐 beat 翻转；mode 1 保留 `0000/FFFF` 逐 beat 写压力图案。
- GF 调度默认值为 `ACT/RD/WR/PRE = 6/11/11/7 CK`，refresh batch 为 `8`。
- RDC 默认扫描 `0..500`、step `1`，启用双 pattern。
- PMIC VDDQ 使用 `0x00B4`，约为 `0.703 V`。
- AD5272 RX VREF 使用 RDAC `0x02A`，板上标定约为 `0.20 V`。

## 问题闭环

原配置 RDAC `0x015` 对应约 `0.10 V`，RDC 可以训练通过，但高压力 GF 会偶发单根 DQ
错误。将 VREF 直接提高到 RDAC `0x035`、约 `0.26 V` 后，DQ00、DQ04 和 DQ07
完全无训练窗口，DQ15 只剩 `2 tap`，说明判决门限已经越过部分弱通道的有效眼区。

VREF 回调到 RDAC `0x02A`、约 `0.20 V` 后，RDC 眼图和 GF 测试恢复通过。当前故障
已定位为板级 RX 判决门限不合适，不是读采集窗口、ISERDES 边界或 GF 调度错误。

## RDC 压力图案

- Pattern 0：MR33/MR34=`5A/A5`，每根 DQ 的 BL16 时间序列为
  `01011010_10100101`，相邻 DQ 反相。
- Pattern 1：MR33/MR34=`3C/C3`，每根 DQ 的 BL16 时间序列为
  `00111100_11000011`，相邻 DQ 反相。
- 两轮扫描取同一 tap 的通过交集，采集窗口、WCK 和 IDELAY 扫描节奏不变。
- GF mode 1 在每个 BL16 内产生 `0000, FFFF, 0000, FFFF...`，反向 pass 使用反相序列。

## 后续验证

1. 固定 RDAC `0x02A`，执行多次断电重上后的完整 `配置 -> 初始化 -> RDC -> GF`。
2. 记录不同板卡的最窄 DQ 窗口和 GF 结果，确认 `0x02A` 的批量稳定性。
3. 需要评估余量时，只在 `0x02A` 附近小步扫描 VREF，不再直接跳到 `0x035`。
4. VREF 稳定性完成统计前，不继续压缩 RD/WR gap，也不改 PHY 时钟和采集窗口。

## 工具

- 扫描工具：`tools/sweep_lp5_rdc_dq_delay.py`。
- 完整流程工具：`tools/run_lp5_debug.py`。
- 量产配置：`tools/KU035_DIE_TEST_LP5_20260608.json`。
- 当前寄存器与默认参数：`doc/2026-07-08_LP5调试配置参数说明.md`。
