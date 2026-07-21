# -*- coding: utf-8 -*-
"""Unified LP5 board debug runner.

Default flow:
    configure board -> init -> RDC train -> GF

Example:
    python tools/run_lp5_debug.py --port COM4
    python tools/run_lp5_debug.py --port COM4 --no-rdc-train
    python tools/run_lp5_debug.py --port COM4 --skip-gf
    python tools/run_lp5_debug.py --port COM4 --gf-only --skip-config
"""

import argparse
import time

import serial


# =============================================================================
# 用户调试参数区
# 日常板级调试优先修改本区；下面的协议地址和命令编码通常不需要改。
# =============================================================================

# 串口配置。
DEFAULT_PORT = "COM4"
DEFAULT_BAUDRATE = 115200

# 默认测试流程：初始化中执行RDC训练，随后执行IDD6N，最后执行GF。
DEFAULT_RDC_TRAIN = True
DEFAULT_RUN_IDD = True
DEFAULT_RUN_GF = True
DEFAULT_GF_REPEAT = 1

# 板级接收参考电压VREF。
# AD5272 RDAC=0x2E约为0.21~0.22 V，作为当前VREF小步上调试验值。
DEFAULT_RX_VREF_RDAC = 0x2E

# RDC扫描范围和训练方式。
# tap范围为0..511；step=1精度最高，但扫描时间也最长。
# dual_pattern=True表示使用双图案交集确定每根DQ的有效窗口。
DEFAULT_RDC_TRAIN_DQ_START = 0
DEFAULT_RDC_TRAIN_DQ_END = 15
DEFAULT_RDC_TRAIN_TAP_START = 0
DEFAULT_RDC_TRAIN_TAP_STOP = 500
DEFAULT_RDC_TRAIN_TAP_STEP = 1
DEFAULT_RDC_TRAIN_DUAL_PATTERN = True
DEFAULT_RDC_TRAIN_TIMEOUT = 240.0
DEFAULT_RDC_TRAIN_POLL_INTERVAL = 0.50
DEFAULT_RDC_DIAGRAM_WIDTH = 80

# RDC前的可选DQ IDELAY初值，单位为tap。
# 默认全部为0；命令行--dqN-delay可以单独覆盖某根DQ。
DEFAULT_DQ_DELAYS = [
    0x000, 0x000, 0x000, 0x000,
    0x000, 0x000, 0x000, 0x000,
    0x000, 0x000, 0x000, 0x000,
    0x000, 0x000, 0x000, 0x000,
]

# INIT/MR8/RDC读采集参数。
# capture_start：发出读命令后，从哪个200M计数开始打开6周期采集窗口。
# beat_offset：从6周期缓存中选择哪一个beat作为16-beat突发起点。
DEFAULT_READ_CAPTURE_START = 0x11
DEFAULT_INIT_BEAT_OFFSET = 1

# GF读采集参数，含义与上面的INIT采集参数相同。
DEFAULT_GF_CAPTURE_START = 0x11
DEFAULT_GF_BEAT_OFFSET = 1

# GF的WCK窗口和事务结束计数，单位均为clk_200m周期。
# 这些值已经按当前RL/WL和PHY窗口验证，普通调度提速时不要一起修改。
DEFAULT_RD_WCK_START = 5
DEFAULT_RD_WCK_LAST = 20
DEFAULT_GF_READ_DONE_CNT = 23
DEFAULT_WR_WCK_START = 5
DEFAULT_WR_WCK_LAST = 18
DEFAULT_GF_WRITE_DONE_CNT = 18

# GF bank-stream命令间隔，单位为clk_200m周期，合法范围0..64。
# ACT：同一row下相邻bank的激活间隔。
# RD ：同一col下相邻bank的读命令及采集slot间隔。
# WR ：同一col下相邻bank的写命令及数据slot间隔。
# PRE：保留寄存器字段；当前PREab只发送一次。
# 配置为0时由RTL采用内部默认值。
DEFAULT_GF_ACT_CMD_GAP = 6
DEFAULT_GF_RD_CMD_GAP = 11
DEFAULT_GF_WR_CMD_GAP = 11
DEFAULT_GF_PRE_CMD_GAP = 7

# 每次集中补刷新的次数，仅支持1、4、8；8速度最快。
DEFAULT_GF_REFRESH_BATCH = 8

# GF测试图案：0=地址/反地址逐beat翻转；1=0000/FFFF写压力图案。
DEFAULT_GF_PATTERN_MODE =0

# 串口收发和轮询等待时间，单位为秒。
SERIAL_TIMEOUT = 0.05
RESPONSE_TIMEOUT = 3.0
COMMAND_DELAY = 0.20
RESULT_TIMEOUT = 300.0
INIT_FIRST_READ_DELAY = 0.50
INIT_POLL_INTERVAL = 0.20
POST_CONFIG_DELAY = 1.00


# =============================================================================
# 协议内部常量
# =============================================================================
FRAME_LEN = 22
MAX_GF_STREAM_GAP = 64

runtime_command_delay = COMMAND_DELAY
runtime_init_first_read_delay = INIT_FIRST_READ_DELAY
runtime_init_poll_interval = INIT_POLL_INTERVAL

# init轮询中打印RDC训练失败结果时使用，由set_bar06_rdc_train_config_command更新。
runtime_rdc_train_dq_start = DEFAULT_RDC_TRAIN_DQ_START
runtime_rdc_train_dq_end = DEFAULT_RDC_TRAIN_DQ_END
runtime_rdc_train_tap_start = DEFAULT_RDC_TRAIN_TAP_START
runtime_rdc_train_tap_stop = DEFAULT_RDC_TRAIN_TAP_STOP

CMD_READ = 0x66
CMD_WRITE = 0x77

ADDR_VERSION = 0x0000
ADDR_PMIC_U68 = 0x0300
ADDR_AD5272 = 0x0308
ADDR_SWITCH = 0x0318
ADDR_INIT_START = 0x0404
ADDR_INIT_RESULT = 0x0408
ADDR_IDD6_START = 0x040C
ADDR_IDD6_RESULT = 0x0410
ADDR_GF_START = 0x0500
ADDR_GF_RESULT = 0x0504
ADDR_GF_AUX_RESULT = 0x0508
ADDR_BAR06_MRW = 0x0608
ADDR_BAR06_DQ_DELAY_L = 0x0618
ADDR_BAR06_RDC_STATUS = 0x0620
ADDR_BAR06_DQ_DELAY_H = 0x0624
ADDR_BAR06_RDC_TRAIN_CTRL = 0x0628
ADDR_BAR06_RDC_TRAIN_STATUS = 0x062C
ADDR_BAR06_RDC_TRAIN_BEST_L = 0x0630
ADDR_BAR06_RDC_TRAIN_BEST_H = 0x0634
ADDR_BAR06_RDC_TRAIN_LEFT_L = 0x0638
ADDR_BAR06_RDC_TRAIN_LEFT_H = 0x063C
ADDR_BAR06_RDC_TRAIN_RIGHT_L = 0x0640
ADDR_BAR06_RDC_TRAIN_RIGHT_H = 0x0644
ADDR_BAR06_CAPTURE_CFG = 0x0648
ADDR_BAR06_GF_STREAM_CFG = 0x064C
ADDR_BAR06_GF_PATTERN_CFG = 0x0650
ADDR_BAR06_RDC_TRAIN_SCAN = 0x0654

GF_STATUS_PASS = 0xC9
GF_STATUS_FAIL = 0x9C
INIT_STATUS_PASS = 0xC9
INIT_STATUS_FAIL = 0x9C

LP5_DENSITY_CODES = {
    0x0C: "LPDDR5 6Gb",
    0x0D: "LPDDR5X 6Gb",
    0x10: "LPDDR5 8Gb",
    0x11: "LPDDR5X 8Gb",
    0x14: "LPDDR5 12Gb",
    0x15: "LPDDR5X 12Gb",
    0x18: "LPDDR5 16Gb",
    0x19: "LPDDR5X 16Gb",
}


def pad12(payload):
    data = list(payload)
    if len(data) > 12:
        raise ValueError("payload must be 12 bytes or less")
    return data + [0x00] * (12 - len(data))


def make_frame(rw, addr, payload=None, cs=0x01):
    body = [cs, rw, addr & 0xFF, (addr >> 8) & 0xFF] + pad12(payload or [])
    return bytes([0xAA, 0x55] + body + [sum(body) & 0xFF, 0x00, 0x55, 0xAA])


def pack_bar06_dq_delay_payload(delay_values):
    """Pack eight 9-bit DQ IDELAY taps into BAR06 DQ delay payload."""
    value = 0
    for index, delay in enumerate(delay_values):
        value |= (delay & 0x1FF) << (9 * index)
    return [(value >> (8 * index)) & 0xFF for index in range(12)]


def pack_int_payload(value):
    return [(value >> (8 * index)) & 0xFF for index in range(12)]


def pack_bar06_capture_cfg_payload(read_capture_start, gf_capture_start,
                                   init_beat_offset,
                                   gf_beat_offset, rd_wck_start, rd_wck_last,
                                   wr_wck_start, wr_wck_last,
                                   gf_read_done_cnt, gf_write_done_cnt):
    """Pack BAR06 CAPTURE_CFG fields exactly like bar06.sv sir_wdat bits."""
    value = 0
    value |= (read_capture_start & 0xFF)
    value |= (gf_capture_start & 0xFF) << 8
    value |= (init_beat_offset & 0xF) << 16
    value |= (gf_beat_offset & 0xF) << 20
    value |= (rd_wck_start & 0x3FF) << 24
    value |= (rd_wck_last & 0x3FF) << 34
    value |= (wr_wck_start & 0x3FF) << 44
    value |= (wr_wck_last & 0x3FF) << 54
    value |= (gf_read_done_cnt & 0x3FF) << 64
    value |= (gf_write_done_cnt & 0x3FF) << 74
    return [(value >> (8 * index)) & 0xFF for index in range(12)]


def pack_bar06_gf_stream_cfg_payload(act_gap, rd_gap, wr_gap, pre_gap,
                                     refresh_batch):
    """Pack BAR06 GF_STREAM_CFG gaps and refresh batch fields."""
    refresh_batch_code = 0 if refresh_batch == 8 else refresh_batch
    value = 0
    value |= (act_gap & 0x3FF)
    value |= (rd_gap & 0x3FF) << 10
    value |= (wr_gap & 0x3FF) << 20
    value |= (pre_gap & 0x3FF) << 30
    value |= (refresh_batch_code & 0x7) << 40
    return [(value >> (8 * index)) & 0xFF for index in range(12)]


def pack_bar06_gf_pattern_cfg_payload(pattern_mode):
    """Pack BAR06 GF_PATTERN_CFG. 0=address toggle, 1=write stress."""
    return pack_int_payload(pattern_mode & 0x3)


COMMANDS = {
    "read_version": make_frame(CMD_READ, ADDR_VERSION),

    # AD5272第4路控制板级RX VREF，当前试验值0x2E，约为0.21~0.22 V。
    "ad5272_1": make_frame(CMD_WRITE, ADDR_AD5272, [0x03, 0x1C, 0x00, 0x10]),
    "ad5272_2": make_frame(CMD_WRITE, ADDR_AD5272, [0x66, 0x05, 0x00, 0x10]),
    "ad5272_3": make_frame(CMD_WRITE, ADDR_AD5272, [0x03, 0xDC, 0x00, 0x10]),
    "ad5272_4": make_frame(
        CMD_WRITE,
        ADDR_AD5272,
        [DEFAULT_RX_VREF_RDAC, 0xC4, 0x00, 0x10],
    ),

    # PMIC U68 VOUTMAX.
    "pmic5401_voutmax_1": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_2": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x80, 0x02, 0x24, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_3": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x01, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_4": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x80, 0x02, 0x24, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_5": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x02, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_6": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x80, 0x02, 0x24, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_7": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x03, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_voutmax_8": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x80, 0x02, 0x24, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),

    # PMIC U68 nominal voltage/current setup.
    "pmic5401_1": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_2": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xCD, 0x01, 0x21, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_3": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xF8, 0x00, 0x47, 0x00, 0xFF]),
    "pmic5401_4": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x01, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_5": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xE6, 0x00, 0x21, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_6": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xF8, 0x00, 0x47, 0x00, 0xFF]),
    "pmic5401_7": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x02, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_8": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x0C, 0x01, 0x21, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_9": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xF8, 0x00, 0x47, 0x00, 0xFF]),
    "pmic5401_10": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0x03, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_11": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xB4, 0x00, 0x21, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]),
    "pmic5401_12": make_frame(CMD_WRITE, ADDR_PMIC_U68, [0xF8, 0x00, 0x47, 0x00, 0xFF]),

    # LP5 capture timing and board switch setup.
    "bar06_dq_delay_l_read": make_frame(CMD_READ, ADDR_BAR06_DQ_DELAY_L),
    "bar06_dq_delay_h_read": make_frame(CMD_READ, ADDR_BAR06_DQ_DELAY_H),
    "bar06_capture_cfg": make_frame(
        CMD_WRITE,
        ADDR_BAR06_CAPTURE_CFG,
        pack_bar06_capture_cfg_payload(
            DEFAULT_READ_CAPTURE_START,
            DEFAULT_GF_CAPTURE_START,
            DEFAULT_INIT_BEAT_OFFSET,
            DEFAULT_GF_BEAT_OFFSET,
            DEFAULT_RD_WCK_START,
            DEFAULT_RD_WCK_LAST,
            DEFAULT_WR_WCK_START,
            DEFAULT_WR_WCK_LAST,
            DEFAULT_GF_READ_DONE_CNT,
            DEFAULT_GF_WRITE_DONE_CNT,
        ),
    ),
    "bar06_capture_cfg_read": make_frame(CMD_READ, ADDR_BAR06_CAPTURE_CFG),
    "bar06_gf_stream_cfg": make_frame(
        CMD_WRITE,
        ADDR_BAR06_GF_STREAM_CFG,
        pack_bar06_gf_stream_cfg_payload(
            DEFAULT_GF_ACT_CMD_GAP,
            DEFAULT_GF_RD_CMD_GAP,
            DEFAULT_GF_WR_CMD_GAP,
            DEFAULT_GF_PRE_CMD_GAP,
            DEFAULT_GF_REFRESH_BATCH,
        ),
    ),
    "bar06_gf_stream_cfg_read": make_frame(CMD_READ, ADDR_BAR06_GF_STREAM_CFG),
    "bar06_gf_pattern_cfg": make_frame(
        CMD_WRITE,
        ADDR_BAR06_GF_PATTERN_CFG,
        pack_bar06_gf_pattern_cfg_payload(DEFAULT_GF_PATTERN_MODE),
    ),
    "bar06_gf_pattern_cfg_read": make_frame(CMD_READ, ADDR_BAR06_GF_PATTERN_CFG),
    "rdc_status": make_frame(CMD_READ, ADDR_BAR06_RDC_STATUS),
    "open_g3vm_for_init": make_frame(
        CMD_WRITE, ADDR_SWITCH, [0x00, 0x00, 0x48, 0x02, 0x8D, 0x02, 0x1B, 0x00]
    ),

    # Initialization commands.
    "init_start": make_frame(CMD_WRITE, ADDR_INIT_START, [0xFF, 0xFF]),
    "init_read": make_frame(CMD_READ, ADDR_INIT_RESULT),
    "idd6_start": make_frame(CMD_WRITE, ADDR_IDD6_START, [0xFF, 0xFF]),
    "idd6_read": make_frame(CMD_READ, ADDR_IDD6_RESULT, [0xFF, 0xFF]),
    "gf_start": make_frame(CMD_WRITE, ADDR_GF_START, [0xFF, 0xFF]),
    "gf_read": make_frame(CMD_READ, ADDR_GF_RESULT, [0xFF, 0xFF]),
    "gf_aux_read": make_frame(CMD_READ, ADDR_GF_AUX_RESULT),
}


CONFIG_SEQUENCE = [
    "read_version",
    "ad5272_1",
    "ad5272_2",
    "ad5272_3",
    "ad5272_4",
    "pmic5401_voutmax_1",
    "pmic5401_voutmax_2",
    "pmic5401_voutmax_3",
    "pmic5401_voutmax_4",
    "pmic5401_voutmax_5",
    "pmic5401_voutmax_6",
    "pmic5401_voutmax_7",
    "pmic5401_voutmax_8",
    "pmic5401_1",
    "pmic5401_2",
    "pmic5401_3",
    "pmic5401_4",
    "pmic5401_5",
    "pmic5401_6",
    "pmic5401_7",
    "pmic5401_8",
    "pmic5401_9",
    "pmic5401_10",
    "pmic5401_11",
    "pmic5401_12",
    "bar06_capture_cfg",
    "bar06_gf_stream_cfg",
    "bar06_gf_pattern_cfg",
    "open_g3vm_for_init",
]


def format_hex(data):
    return " ".join(f"{item:02X}" for item in data)


def checksum(frame):
    return sum(frame[2:18]) & 0xFF


def frame_addr(frame):
    return (frame[5] << 8) | frame[4]


def payload(frame):
    return frame[6:18]


def validate_frame(frame, name):
    if len(frame) != FRAME_LEN:
        raise ValueError(f"{name}: frame length is {len(frame)}, expected {FRAME_LEN}")
    if frame[0:2] != b"\xAA\x55" or frame[-2:] != b"\x55\xAA":
        raise ValueError(f"{name}: bad frame head/tail: {format_hex(frame)}")
    if frame[18] != checksum(frame):
        raise ValueError(
            f"{name}: bad checksum, got {frame[18]:02X}, expected {checksum(frame):02X}: "
            f"{format_hex(frame)}"
        )


def read_response(port, name):
    deadline = time.monotonic() + RESPONSE_TIMEOUT
    data = bytearray()

    while time.monotonic() < deadline:
        byte = port.read(1)
        if not byte:
            continue
        data.append(byte[0])
        if len(data) > 2:
            del data[:-2]
        if data == bytearray([0xAA, 0x55]):
            break
    else:
        raise TimeoutError(f"{name}: response header AA 55 not received")

    while len(data) < FRAME_LEN:
        chunk = port.read(FRAME_LEN - len(data))
        if chunk:
            data.extend(chunk)
        elif time.monotonic() >= deadline:
            raise TimeoutError(f"{name}: response timeout: {format_hex(data)}")

    frame = bytes(data)
    validate_frame(frame, name)
    if frame[3] != 0x88:
        raise ValueError(f"{name}: FPGA returned status 0x{frame[3]:02X}: {format_hex(frame)}")
    return frame


def send_command(port, name):
    frame = COMMANDS[name]
    validate_frame(frame, name)

    print(f"TX {name:25s} addr=0x{frame_addr(frame):04X}: {format_hex(frame)}")
    port.reset_input_buffer()
    port.write(frame)
    port.flush()

    response = read_response(port, name)
    print(f"RX {name:25s} addr=0x{frame_addr(response):04X}: {format_hex(response)}")
    time.sleep(runtime_command_delay)
    return response


def send_runtime_mrw(port, ma, op):
    """Fire one runtime MRW through bar06 mrw_r: [6:0]=MA, [14:8]=OP[6:0],
    [15]=OP7, [16]=trigger rising edge."""
    value = (ma & 0x7F) | ((op & 0x7F) << 8) | (((op >> 7) & 1) << 15)
    COMMANDS["mrw_fire_low"] = make_frame(
        CMD_WRITE, ADDR_BAR06_MRW, pack_int_payload(value))
    COMMANDS["mrw_fire_high"] = make_frame(
        CMD_WRITE, ADDR_BAR06_MRW, pack_int_payload(value | (1 << 16)))
    print(f"runtime MRW: MR{ma} = 0x{op:02X}")
    send_command(port, "mrw_fire_low")
    send_command(port, "mrw_fire_high")
    send_command(port, "mrw_fire_low")
    time.sleep(0.05)


def set_bar06_capture_cfg_command(read_capture_start, gf_capture_start,
                                  init_beat_offset,
                                  gf_beat_offset, rd_wck_start, rd_wck_last,
                                  wr_wck_start, wr_wck_last,
                                  gf_read_done_cnt, gf_write_done_cnt):
    COMMANDS["bar06_capture_cfg"] = make_frame(
        CMD_WRITE,
        ADDR_BAR06_CAPTURE_CFG,
        pack_bar06_capture_cfg_payload(
            read_capture_start,
            gf_capture_start,
            init_beat_offset,
            gf_beat_offset,
            rd_wck_start,
            rd_wck_last,
            wr_wck_start,
            wr_wck_last,
            gf_read_done_cnt,
            gf_write_done_cnt,
        ),
    )


def set_bar06_gf_stream_cfg_command(act_gap, rd_gap, wr_gap, pre_gap,
                                     refresh_batch):
    COMMANDS["bar06_gf_stream_cfg"] = make_frame(
        CMD_WRITE,
        ADDR_BAR06_GF_STREAM_CFG,
        pack_bar06_gf_stream_cfg_payload(
            act_gap, rd_gap, wr_gap, pre_gap, refresh_batch),
    )


def set_bar06_gf_pattern_cfg_command(pattern_mode):
    COMMANDS["bar06_gf_pattern_cfg"] = make_frame(
        CMD_WRITE,
        ADDR_BAR06_GF_PATTERN_CFG,
        pack_bar06_gf_pattern_cfg_payload(pattern_mode),
    )


def set_bar06_dq_delay_commands(dq_delays):
    COMMANDS["bar06_dq_delay_l"] = make_frame(
        CMD_WRITE,
        ADDR_BAR06_DQ_DELAY_L,
        pack_bar06_dq_delay_payload(dq_delays[0:8]),
    )
    COMMANDS["bar06_dq_delay_h"] = make_frame(
        CMD_WRITE,
        ADDR_BAR06_DQ_DELAY_H,
        pack_bar06_dq_delay_payload(dq_delays[8:16]),
    )


def set_bar06_rdc_train_config_command(dq_start, dq_end, tap_start, tap_stop,
                                        tap_step, apply_best, init_enable,
                                        dual_pattern):
    global runtime_rdc_train_dq_start, runtime_rdc_train_dq_end
    global runtime_rdc_train_tap_start, runtime_rdc_train_tap_stop
    runtime_rdc_train_dq_start = dq_start
    runtime_rdc_train_dq_end = dq_end
    runtime_rdc_train_tap_start = tap_start
    runtime_rdc_train_tap_stop = tap_stop

    ctrl = 0
    ctrl |= (1 if apply_best else 0) << 1
    ctrl |= (1 if init_enable else 0) << 2
    ctrl |= (dq_start & 0xF) << 4
    ctrl |= (dq_end & 0xF) << 8
    ctrl |= (tap_start & 0x1FF) << 12
    ctrl |= (tap_stop & 0x1FF) << 21
    ctrl |= (tap_step & 0x1FF) << 30
    ctrl |= (1 if dual_pattern else 0) << 39

    COMMANDS["rdc_train_cfg"] = make_frame(
        CMD_WRITE,
        ADDR_BAR06_RDC_TRAIN_CTRL,
        pack_int_payload(ctrl),
    )
    COMMANDS["rdc_train_status"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_STATUS)
    COMMANDS["rdc_train_best_l"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_BEST_L)
    COMMANDS["rdc_train_best_h"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_BEST_H)
    COMMANDS["rdc_train_left_l"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_LEFT_L)
    COMMANDS["rdc_train_left_h"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_LEFT_H)
    COMMANDS["rdc_train_right_l"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_RIGHT_L)
    COMMANDS["rdc_train_right_h"] = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_RIGHT_H)


def payload_to_int(data):
    value = 0
    for index, byte in enumerate(data):
        value |= byte << (8 * index)
    return value


def decode_capture_cfg(frame):
    value = payload_to_int(payload(frame))
    return {
        "read_capture_start": value & 0xFF,
        "gf_capture_start": (value >> 8) & 0xFF,
        "init_beat_offset": (value >> 16) & 0xF,
        "gf_beat_offset": (value >> 20) & 0xF,
        "rd_wck_start": (value >> 24) & 0x3FF,
        "rd_wck_last": (value >> 34) & 0x3FF,
        "wr_wck_start": (value >> 44) & 0x3FF,
        "wr_wck_last": (value >> 54) & 0x3FF,
        "gf_read_done_cnt": (value >> 64) & 0x3FF,
        "gf_write_done_cnt": (value >> 74) & 0x3FF,
    }


def decode_gf_stream_cfg(frame):
    value = payload_to_int(payload(frame))
    refresh_batch_code = (value >> 40) & 0x7
    return {
        "act_gap": value & 0x3FF,
        "rd_gap": (value >> 10) & 0x3FF,
        "wr_gap": (value >> 20) & 0x3FF,
        "pre_gap": (value >> 30) & 0x3FF,
        "refresh_batch": 8 if refresh_batch_code == 0 else refresh_batch_code,
    }


def decode_gf_pattern_cfg(frame):
    value = payload_to_int(payload(frame))
    return {
        "pattern_mode": value & 0x3,
    }


def decode_rdc_status(frame):
    value = payload_to_int(payload(frame))
    return {
        "err_bitmap": value & 0xFFFF,
        "valid": (value >> 16) & 0x1,
        "pass": (value >> 17) & 0x1,
    }


def decode_gf_addr(value):
    col = value & 0x3F
    row = (value >> 6) & 0x3FFFF
    bg = (value >> 24) & 0x3
    ba = (value >> 26) & 0x3
    return f"ba={ba} bg={bg} row=0x{row:05X} col={col}"


def decode_gf_aux(data):
    value = payload_to_int(data)
    count = gf_aux_fail_count(data)
    addr0 = value & 0x0FFFFFFF
    addr1 = (value >> 28) & 0x0FFFFFFF
    addr2 = (value >> 56) & 0x0FFFFFFF
    addrs = [addr0, addr1, addr2]
    shown = min(count, 3)
    if shown == 0:
        return "count=0"
    return (
        f"count={count}, first_rows=["
        + "; ".join(decode_gf_addr(addrs[index]) for index in range(shown))
        + "]"
    )


def gf_aux_fail_count(data):
    value = payload_to_int(data)
    return (value >> 84) & 0xF


def print_capture_config_readback(port):
    capture_frame = send_command(port, "bar06_capture_cfg_read")
    capture_cfg = decode_capture_cfg(capture_frame)

    print(
        "capture_cfg: "
        f"read_capture_start=0x{capture_cfg['read_capture_start']:02X} "
        f"gf_capture_start=0x{capture_cfg['gf_capture_start']:02X} "
        f"init_beat_offset={capture_cfg['init_beat_offset']} "
        f"gf_beat_offset={capture_cfg['gf_beat_offset']} "
        f"rd_wck={capture_cfg['rd_wck_start']}..{capture_cfg['rd_wck_last']} "
        f"wr_wck={capture_cfg['wr_wck_start']}..{capture_cfg['wr_wck_last']} "
        f"read_done={capture_cfg['gf_read_done_cnt']} "
        f"write_done={capture_cfg['gf_write_done_cnt']}"
    )
    print()


def print_gf_stream_config_readback(port):
    stream_frame = send_command(port, "bar06_gf_stream_cfg_read")
    stream_cfg = decode_gf_stream_cfg(stream_frame)

    print(
        "gf_stream_cfg: "
        f"act_gap={stream_cfg['act_gap']} "
        f"rd_gap={stream_cfg['rd_gap']} "
        f"wr_gap={stream_cfg['wr_gap']} "
        f"pre_gap={stream_cfg['pre_gap']} "
        f"refresh_batch={stream_cfg['refresh_batch']}"
    )
    print()


def print_gf_pattern_config_readback(port):
    pattern_frame = send_command(port, "bar06_gf_pattern_cfg_read")
    pattern_cfg = decode_gf_pattern_cfg(pattern_frame)
    pattern_names = {
        0: "address-toggle",
        1: "write-stress-0000/ffff",
    }
    pattern_mode = pattern_cfg["pattern_mode"]

    print(
        "gf_pattern_cfg: "
        f"mode={pattern_mode} "
        f"({pattern_names.get(pattern_mode, 'reserved')})"
    )
    print()


def print_rdc_status(status):
    print(
        f"rdc_status: valid={status['valid']} pass={status['pass']} "
        f"err_bitmap=0x{status['err_bitmap']:04X}"
    )


def send_command_quiet(port, name):
    frame = COMMANDS[name]
    validate_frame(frame, name)

    port.reset_input_buffer()
    port.write(frame)
    port.flush()

    response = read_response(port, name)
    time.sleep(runtime_command_delay)
    return response


def send_frame_quiet(port, name, frame, delay_s=0.01):
    validate_frame(frame, name)

    port.reset_input_buffer()
    port.write(frame)
    port.flush()

    response = read_response(port, name)
    time.sleep(delay_s)
    return response


def read_command_int(port, name, quiet=True):
    if quiet:
        frame = send_command_quiet(port, name)
    else:
        frame = send_command(port, name)
    return payload_to_int(payload(frame))


def read_rdc_train_scan_map(port, tap_start, tap_stop, tap_step):
    select_value = tap_start | (tap_step << 9)
    select_frame = make_frame(
        CMD_WRITE,
        ADDR_BAR06_RDC_TRAIN_SCAN,
        pack_int_payload(select_value),
    )
    read_frame = make_frame(CMD_READ, ADDR_BAR06_RDC_TRAIN_SCAN)
    send_frame_quiet(port, "rdc_train_scan_select", select_frame)

    scan_map = {}
    for expected_tap in range(tap_start, tap_stop + 1, tap_step):
        response = send_frame_quiet(port, "rdc_train_scan_read", read_frame)
        value = payload_to_int(payload(response))
        read_tap = value & 0x1FF
        read_step = (value >> 9) & 0x1FF
        pass_bitmap = (value >> 18) & 0xFFFF

        if read_tap != expected_tap:
            raise RuntimeError(
                f"RDC scan readback tap mismatch: expected={expected_tap} "
                f"read={read_tap}"
            )
        if read_step != tap_step:
            raise RuntimeError(
                f"RDC scan readback step mismatch: expected={tap_step} "
                f"read={read_step}"
            )
        scan_map[read_tap] = pass_bitmap

    return scan_map


def format_tap_ranges(taps, tap_step):
    if not taps:
        return "none"

    ranges = []
    range_start = taps[0]
    range_stop = taps[0]
    for tap in taps[1:]:
        if tap == range_stop + tap_step:
            range_stop = tap
        else:
            ranges.append((range_start, range_stop))
            range_start = tap
            range_stop = tap
    ranges.append((range_start, range_stop))

    return ", ".join(
        str(start) if start == stop else f"{start}..{stop}"
        for start, stop in ranges
    )


def print_rdc_train_scan_map(scan_map, dq_start, dq_end, tap_step, line_width):
    taps = sorted(scan_map)
    print("RDC full scan map: '=' PASS, '.' FAIL")

    for dq_index in range(dq_start, dq_end + 1):
        pass_taps = [tap for tap in taps if (scan_map[tap] >> dq_index) & 0x1]
        hole_taps = []
        if pass_taps:
            first_pass = pass_taps[0]
            last_pass = pass_taps[-1]
            hole_taps = [
                tap for tap in taps
                if first_pass < tap < last_pass and
                ((scan_map[tap] >> dq_index) & 0x1) == 0
            ]

        print(f"DQ{dq_index:02d}")
        for offset in range(0, len(taps), line_width):
            chunk_taps = taps[offset:offset + line_width]
            symbols = "".join(
                "=" if (scan_map[tap] >> dq_index) & 0x1 else "."
                for tap in chunk_taps
            )
            print(f"  {chunk_taps[0]:03d}..{chunk_taps[-1]:03d}: {symbols}")
        print(f"  PASS ranges: {format_tap_ranges(pass_taps, tap_step)}")
        print(f"  FAIL holes:  {format_tap_ranges(hole_taps, tap_step)}")


def decode_rdc_train_status_value(value):
    return {
        "busy": value & 0x1,
        "done": (value >> 1) & 0x1,
        "pass_all": (value >> 2) & 0x1,
        "init_done": (value >> 3) & 0x1,
        "state": (value >> 13) & 0xF,
        "dq_start": (value >> 17) & 0xF,
        "tap": (value >> 21) & 0x1FF,
        "best_len": (value >> 30) & 0x3FF,
        "last_err_bitmap": (value >> 40) & 0xFFFF,
        "pass_mask": (value >> 56) & 0xFFFF,
        "fail_mask": (value >> 72) & 0xFFFF,
    }


def print_rdc_train_status(prefix, status):
    print(
        f"{prefix}: busy={status['busy']} done={status['done']} "
        f"pass_all={status['pass_all']} init_done={status['init_done']} "
        f"state={status['state']} dq_start={status['dq_start']} tap={status['tap']} "
        f"best_len={status['best_len']} "
        f"last_err=0x{status['last_err_bitmap']:04X} "
        f"pass_mask=0x{status['pass_mask']:04X} "
        f"fail_mask=0x{status['fail_mask']:04X}"
    )


def wait_rdc_train_done(port, timeout_s, poll_interval_s, verbose_poll):
    deadline = time.monotonic() + timeout_s
    last_status = None
    last_print_time = 0.0
    idle_poll_count = 0
    wait_init_poll_count = 0

    while time.monotonic() < deadline:
        value = read_command_int(port, "rdc_train_status", quiet=not verbose_poll)
        status = decode_rdc_train_status_value(value)
        now = time.monotonic()

        if (
            last_status is None
            or status["state"] != last_status["state"]
            or status["dq_start"] != last_status["dq_start"]
            or status["tap"] != last_status["tap"]
            or status["done"] != last_status["done"]
            or now - last_print_time >= 5.0
        ):
            print_rdc_train_status("rdc_train", status)
            last_print_time = now

        if status["done"] and not status["busy"]:
            return status

        if not status["busy"] and not status["done"]:
            idle_poll_count += 1
            if idle_poll_count >= 3:
                raise RuntimeError(
                    "rdc_train did not start. Check that the freshly built bitstream "
                    "is programmed and BAR06 0x0628/0x062c registers exist in the FPGA."
                )
        else:
            idle_poll_count = 0

        if status["busy"] and status["state"] == 1 and not status["init_done"]:
            wait_init_poll_count += 1
            if wait_init_poll_count >= 10:
                raise RuntimeError(
                    "rdc_train is waiting for init_done. Run full LP5 init first, "
                    "or check why init_done is not set."
                )
        else:
            wait_init_poll_count = 0

        last_status = status
        time.sleep(poll_interval_s)

    raise TimeoutError(f"rdc_train timeout, last_status={last_status}")


def read_9bit_flat16(port, low_name, high_name):
    low = read_command_int(port, low_name) & ((1 << 72) - 1)
    high = read_command_int(port, high_name) & ((1 << 72) - 1)
    value = low | (high << 72)
    return [(value >> (9 * index)) & 0x1FF for index in range(16)]


def print_dq_delay_readback(port, title):
    dq_delay = read_9bit_flat16(port, "bar06_dq_delay_l_read", "bar06_dq_delay_h_read")
    print(title)
    print(
        "  decimal: "
        + " ".join(f"DQ{index:02d}={delay}" for index, delay in enumerate(dq_delay))
    )
    print(
        "  hex:     "
        + " ".join(f"DQ{index:02d}=0x{delay:03X}" for index, delay in enumerate(dq_delay))
    )
    print()
    return dq_delay


def draw_rdc_window(left, right, best, passed, diagram_start, diagram_stop, max_width):
    span = diagram_stop - diagram_start + 1
    width = min(span, max_width)
    chars = []

    for column in range(width):
        bin_left = diagram_start + (span * column) // width
        bin_right = diagram_start + (span * (column + 1)) // width - 1
        if passed and bin_left <= best <= bin_right:
            chars.append("B")
        elif passed and not (right < bin_left or left > bin_right):
            chars.append("=")
        else:
            chars.append(".")

    return "".join(chars)


def print_rdc_train_result(status, best, left, right, dq_start, dq_end,
                           diagram_start, diagram_stop, diagram_width):
    print()
    print("RDC train result:")
    print(
        f"  pass_all={status['pass_all']} "
        f"pass_mask=0x{status['pass_mask']:04X} "
        f"fail_mask=0x{status['fail_mask']:04X}"
    )
    print(
        f"  diagram tap range={diagram_start}..{diagram_stop}, "
        "legend: '=' pass window, 'B' best tap, '.' outside/fail"
    )
    print()
    print("DQ   RESULT  LEFT  RIGHT  BEST  WIDTH  WINDOW")

    for dq in range(16):
        selected = dq_start <= dq <= dq_end
        passed = ((status["pass_mask"] >> dq) & 1) == 1
        failed = ((status["fail_mask"] >> dq) & 1) == 1

        if not selected:
            result = "SKIP"
        elif passed:
            result = "OK"
        elif failed:
            result = "FAIL"
        else:
            result = "NONE"

        if passed:
            width = right[dq] - left[dq] + 1
            diagram = draw_rdc_window(
                left[dq], right[dq], best[dq], True,
                diagram_start, diagram_stop, diagram_width,
            )
            print(
                f"DQ{dq:02d} {result:>6s}  "
                f"{left[dq]:4d}  {right[dq]:5d}  {best[dq]:4d}  {width:5d}  {diagram}"
            )
        else:
            diagram = draw_rdc_window(
                0, 0, 0, False,
                diagram_start, diagram_stop, diagram_width,
            )
            print(
                f"DQ{dq:02d} {result:>6s}  "
                f"{'----':>4s}  {'----':>5s}  {'----':>4s}  {'----':>5s}  {diagram}"
            )


def report_rdc_train_windows(port, status):
    """Read the RDC window registers and print the per-lane result table."""
    best = read_9bit_flat16(port, "rdc_train_best_l", "rdc_train_best_h")
    left = read_9bit_flat16(port, "rdc_train_left_l", "rdc_train_left_h")
    right = read_9bit_flat16(port, "rdc_train_right_l", "rdc_train_right_h")
    print_rdc_train_result(
        status,
        best,
        left,
        right,
        runtime_rdc_train_dq_start,
        runtime_rdc_train_dq_end,
        runtime_rdc_train_tap_start,
        runtime_rdc_train_tap_stop,
        DEFAULT_RDC_DIAGRAM_WIDTH,
    )


def init_result_ready(frame):
    data = payload(frame)
    return data[0] == INIT_STATUS_PASS and data[1] in LP5_DENSITY_CODES


def poll_init_result(port, rdc_train_enabled=False):
    deadline = time.monotonic() + RESULT_TIMEOUT
    last_response = None
    last_train_status = None
    last_train_print = 0.0

    while time.monotonic() < deadline:
        last_response = send_command(port, "init_read")
        data = payload(last_response)

        if data[0] == INIT_STATUS_FAIL:
            print(
                f"init_read: result FAIL, status=0x{data[0]:02X}, "
                f"density=0x{data[1]:02X}, payload={format_hex(data)}\n"
            )
            if rdc_train_enabled:
                value = read_command_int(port, "rdc_train_status")
                status = decode_rdc_train_status_value(value)
                print_rdc_train_status("init/rdc_train", status)
                report_rdc_train_windows(port, status)
                raise RuntimeError(
                    "init failed with status=9C: "
                    f"fail_mask=0x{status['fail_mask']:04X} "
                    f"pass_mask=0x{status['pass_mask']:04X} "
                    f"last_err=0x{status['last_err_bitmap']:04X}"
                )
            raise RuntimeError("init failed with status=9C")

        if init_result_ready(last_response):
            print(
                f"init_read: result ready, density={LP5_DENSITY_CODES[data[1]]}, "
                f"payload={format_hex(data)}\n"
            )
            return last_response

        if data[0] == 0xC9:
            print(
                f"init_read: result ready, WARNING density/MR byte is 0x{data[1]:02X}, "
                f"payload={format_hex(data)}"
            )
            print("init_read: continue; MR8 mismatch is not a blocking condition now.\n")
            return last_response

        print(
            f"init_read: result not ready, status=0x{data[0]:02X}, "
            f"density=0x{data[1]:02X}, poll again after {runtime_init_poll_interval:.2f}s\n"
        )

        # init出口现在是fail-stop：RDC训练失败时init永远不会ready。这里必须
        # 同步观测训练状态，否则失败只表现为init超时，什么诊断信息都没有。
        if rdc_train_enabled:
            value = read_command_int(port, "rdc_train_status")
            status = decode_rdc_train_status_value(value)
            now = time.monotonic()
            if (
                last_train_status is None
                or status["state"] != last_train_status["state"]
                or status["done"] != last_train_status["done"]
                or now - last_train_print >= 5.0
            ):
                print_rdc_train_status("init/rdc_train", status)
                last_train_print = now
            last_train_status = status

            if status["done"] and not status["pass_all"]:
                print()
                print(
                    "init_read: rdc_train finished with failures; init is "
                    "fail-stop and will never report ready. Aborting init poll."
                )
                report_rdc_train_windows(port, status)
                raise RuntimeError(
                    "rdc_train failed during init: "
                    f"fail_mask=0x{status['fail_mask']:04X} "
                    f"pass_mask=0x{status['pass_mask']:04X} "
                    f"last_err=0x{status['last_err_bitmap']:04X}"
                )

        time.sleep(runtime_init_poll_interval)

    raise TimeoutError(
        f"init_read: result not ready before timeout, "
        f"last={format_hex(last_response or b'')}, "
        f"rdc_train_last_status={last_train_status}"
    )


def gf_result_ready(frame):
    data = payload(frame)
    return data[0] in (GF_STATUS_PASS, GF_STATUS_FAIL)


def gf_result_pass(frame):
    data = payload(frame)
    return data[0] == GF_STATUS_PASS


def idd_result_ready(frame):
    data = payload(frame)
    return data[0] in (GF_STATUS_PASS, GF_STATUS_FAIL)


def poll_idd_result(port):
    deadline = time.monotonic() + RESULT_TIMEOUT
    last_response = None

    while time.monotonic() < deadline:
        last_response = send_command(port, "idd6_read")
        data = payload(last_response)
        if idd_result_ready(last_response):
            print(f"idd6_read: result ready, payload={format_hex(data)}\n")
            return last_response

        print(
            f"idd6_read: result not ready, status=0x{data[0]:02X}, "
            f"poll again after {runtime_init_poll_interval:.2f}s\n"
        )
        time.sleep(runtime_init_poll_interval)

    raise TimeoutError(
        f"idd6_read: result not ready before timeout, "
        f"last={format_hex(last_response or b'')}"
    )


def poll_gf_result(port):
    deadline = time.monotonic() + RESULT_TIMEOUT
    last_response = None

    while time.monotonic() < deadline:
        last_response = send_command(port, "gf_read")
        data = payload(last_response)
        if gf_result_ready(last_response):
            status_text = "PASS" if gf_result_pass(last_response) else "FAIL"
            print(
                f"gf_read: result {status_text}, status=0x{data[0]:02X}, "
                f"raw={format_hex(data)}\n"
            )
            return last_response

        print(
            f"gf_read: result not ready, status=0x{data[0]:02X}, "
            f"poll again after {runtime_init_poll_interval:.2f}s\n"
        )
        time.sleep(runtime_init_poll_interval)

    raise TimeoutError(
        f"gf_read: result not ready before timeout, "
        f"last={format_hex(last_response or b'')}"
    )


def send_sequence(port, title, sequence):
    print(f"=== {title} ===")
    start = time.monotonic()
    for name in sequence:
        send_command(port, name)
        print()
    elapsed = time.monotonic() - start
    print(f"{title} elapsed: {elapsed:.3f}s\n")
    return elapsed


def run_init(port, no_poll, rdc_train_enabled=False):
    send_command(port, "init_start")
    print()

    if no_poll:
        send_command(port, "init_read")
        print()
        return

    print(f"init_read: wait {runtime_init_first_read_delay:.2f}s before first read\n")
    time.sleep(runtime_init_first_read_delay)
    poll_init_result(port, rdc_train_enabled)


def run_idd6(port, no_poll):
    send_command(port, "idd6_start")
    print()

    if no_poll:
        send_command(port, "idd6_read")
        print()
        return

    poll_idd_result(port)


def run_gf(port, no_poll, repeat):
    for index in range(repeat):
        if repeat > 1:
            print(f"--- GF run {index + 1}/{repeat} ---")

        send_command(port, "gf_start")
        print()

        if no_poll:
            gf_frame = send_command(port, "gf_read")
            print()
        else:
            gf_frame = poll_gf_result(port)

        aux_frame = send_command(port, "gf_aux_read")
        aux_data = payload(aux_frame)
        fail_count = gf_aux_fail_count(aux_data)
        print(f"gf_aux_read: fail summary raw={format_hex(aux_data)}")
        print(f"gf_aux_read: decoded {decode_gf_aux(aux_data)}")
        if gf_result_pass(gf_frame):
            print("GF result: PASS (status=C9)\n")
        else:
            print(f"GF result: FAIL (status=9C, aux fail rows={fail_count})\n")
            raise RuntimeError("GF failed with status=9C")


def main():
    parser = argparse.ArgumentParser(
        description="Unified LP5 debug runner: config, init, RDC train, optional IDD6, and GF."
    )
    parser.add_argument("--port", default=DEFAULT_PORT)
    parser.add_argument("--baudrate", type=int, default=DEFAULT_BAUDRATE)
    parser.add_argument(
        "--skip-config",
        action="store_true",
        help="Skip peripheral and BAR06 configuration writes.",
    )
    parser.add_argument(
        "--config-only",
        action="store_true",
        help="Only write configuration, then exit.",
    )
    parser.add_argument(
        "--no-poll",
        action="store_true",
        help="Send start/read command pairs once without polling result.",
    )
    parser.add_argument(
        "--gf-only",
        action="store_true",
        help="Run GF only after optional config; skip init, RDC train, and IDD6.",
    )
    parser.add_argument(
        "--rdc-train",
        action="store_true",
        default=DEFAULT_RDC_TRAIN,
        help="Enable RDC training inside LP5 init and print the window table.",
    )
    parser.add_argument(
        "--no-rdc-train",
        dest="rdc_train",
        action="store_false",
        help="Run LP5 init without RDC training.",
    )
    parser.add_argument(
        "--rdc-train-dq-start",
        type=lambda value: int(value, 0),
        default=DEFAULT_RDC_TRAIN_DQ_START,
    )
    parser.add_argument(
        "--rdc-train-dq-end",
        type=lambda value: int(value, 0),
        default=DEFAULT_RDC_TRAIN_DQ_END,
    )
    parser.add_argument(
        "--rdc-train-tap-start",
        type=lambda value: int(value, 0),
        default=DEFAULT_RDC_TRAIN_TAP_START,
    )
    parser.add_argument(
        "--rdc-train-tap-stop",
        type=lambda value: int(value, 0),
        default=DEFAULT_RDC_TRAIN_TAP_STOP,
    )
    parser.add_argument(
        "--rdc-train-tap-step",
        type=lambda value: int(value, 0),
        default=DEFAULT_RDC_TRAIN_TAP_STEP,
    )
    parser.add_argument(
        "--rdc-train-no-apply-best",
        action="store_true",
        help="Run training but restore the original DQ delays after the scan.",
    )
    parser.add_argument(
        "--rdc-train-dual-pattern",
        dest="rdc_train_dual_pattern",
        action="store_true",
        default=DEFAULT_RDC_TRAIN_DUAL_PATTERN,
        help=(
            "Train each tap with BL16 5A/A5 and 3C/C3 "
            "patterns with adjacent-DQ inversion, then use the intersection."
        ),
    )
    parser.add_argument(
        "--rdc-train-single-pattern",
        dest="rdc_train_dual_pattern",
        action="store_false",
        help="Train each tap with the BL16 5A/A5 pattern only.",
    )
    parser.add_argument("--rdc-train-timeout", type=float, default=DEFAULT_RDC_TRAIN_TIMEOUT)
    parser.add_argument(
        "--rdc-train-poll-interval",
        type=float,
        default=DEFAULT_RDC_TRAIN_POLL_INTERVAL,
    )
    parser.add_argument("--rdc-train-verbose-poll", action="store_true")
    parser.add_argument(
        "--rdc-print-scan",
        action="store_true",
        help="Read and print every scanned tap PASS/FAIL result after RDC training.",
    )
    parser.add_argument("--rdc-diagram-start", type=lambda value: int(value, 0))
    parser.add_argument("--rdc-diagram-stop", type=lambda value: int(value, 0))
    parser.add_argument("--rdc-diagram-width", type=int, default=DEFAULT_RDC_DIAGRAM_WIDTH)
    parser.add_argument(
        "--read-capture-start",
        type=lambda value: int(value, 0),
        default=DEFAULT_READ_CAPTURE_START,
        help="INIT-path (MRR/RDC) capture start counter. Accepts decimal or 0x-prefixed hex.",
    )
    parser.add_argument(
        "--gf-capture-start",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_CAPTURE_START,
        help="GF READ capture start counter (bar06 CAPTURE_CFG).",
    )
    parser.add_argument(
        "--init-beat-offset",
        type=lambda value: int(value, 0),
        default=DEFAULT_INIT_BEAT_OFFSET,
        help="INIT-path burst slice beat offset, 0..8.",
    )
    parser.add_argument(
        "--gf-beat-offset",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_BEAT_OFFSET,
        help="GF-path burst slice beat offset, 0..8.",
    )
    parser.add_argument(
        "--rd-wck-start",
        type=lambda value: int(value, 0),
        default=DEFAULT_RD_WCK_START,
        help="GF READ WCK window start count.",
    )
    parser.add_argument(
        "--rd-wck-last",
        type=lambda value: int(value, 0),
        default=DEFAULT_RD_WCK_LAST,
        help="GF READ WCK window last count.",
    )
    parser.add_argument(
        "--wr-wck-start",
        type=lambda value: int(value, 0),
        default=DEFAULT_WR_WCK_START,
        help="GF WRITE WCK window start count.",
    )
    parser.add_argument(
        "--wr-wck-last",
        type=lambda value: int(value, 0),
        default=DEFAULT_WR_WCK_LAST,
        help="GF WRITE WCK window last count.",
    )
    parser.add_argument(
        "--gf-read-done-cnt",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_READ_DONE_CNT,
        help="GF READ transaction done count. Legacy default is 39.",
    )
    parser.add_argument(
        "--gf-write-done-cnt",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_WRITE_DONE_CNT,
        help="GF WRITE transaction done count. Legacy default is 27.",
    )
    parser.add_argument(
        "--gf-act-gap",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_ACT_CMD_GAP,
        help="GF bank-stream ACT command gap in clk_200m cycles, 0..64. 0 uses RTL default.",
    )
    parser.add_argument(
        "--gf-rd-gap",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_RD_CMD_GAP,
        help="GF bank-stream READ command/capture slot gap in clk_200m cycles, 0..64. 0 uses RTL default.",
    )
    parser.add_argument(
        "--gf-wr-gap",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_WR_CMD_GAP,
        help="GF bank-stream WRITE command/payload slot gap in clk_200m cycles, 0..64. 0 uses RTL default.",
    )
    parser.add_argument(
        "--gf-rdwr-gap",
        type=lambda value: int(value, 0),
        default=None,
        help="Legacy option: set both --gf-rd-gap and --gf-wr-gap to the same value.",
    )
    parser.add_argument(
        "--gf-pre-gap",
        type=lambda value: int(value, 0),
        default=DEFAULT_GF_PRE_CMD_GAP,
        help="Reserved GF PRE gap field, 0..64. PREab currently uses one command.",
    )
    parser.add_argument(
        "--gf-refresh-batch",
        type=lambda value: int(value, 0),
        choices=(1, 4, 8),
        default=DEFAULT_GF_REFRESH_BATCH,
        help="GF refresh batch size. Supported values are 1, 4, and 8.",
    )
    parser.add_argument(
        "--gf-pattern-mode",
        "--gf-pattern",
        dest="gf_pattern_mode",
        type=lambda value: int(value, 0),
        choices=(0, 1),
        default=DEFAULT_GF_PATTERN_MODE,
        help="GF data pattern: 0=address/beat toggle, 1=write stress 0000/ffff.",
    )
    parser.add_argument(
        "--mrw",
        action="append",
        default=[],
        metavar="MA:OP",
        help="Runtime MRW to fire after init/train, e.g. --mrw 11:0x34. "
             "May repeat.",
    )
    for index, default_delay in enumerate(DEFAULT_DQ_DELAYS):
        parser.add_argument(
            f"--dq{index}-delay",
            type=lambda value: int(value, 0),
            default=None,
            help=f"Optional BAR06 DQ{index} IDELAY tap override, 0..511. RTL default is {default_delay}.",
        )
    for index in range(16):
        parser.add_argument(
            f"--post-rdc-dq{index}-delay",
            type=lambda value: int(value, 0),
            default=None,
            help=(
                f"Optional DQ{index} IDELAY tap override after RDC training, "
                "used to sweep GF read margin without changing the training result."
            ),
        )
    parser.add_argument(
        "--command-delay",
        type=float,
        default=COMMAND_DELAY,
        help="Delay after each serial command response, in seconds.",
    )
    parser.add_argument(
        "--init-first-read-delay",
        type=float,
        default=INIT_FIRST_READ_DELAY,
        help="Delay after init_start before the first init_read poll, in seconds.",
    )
    parser.add_argument(
        "--init-poll-interval",
        type=float,
        default=INIT_POLL_INTERVAL,
        help="Delay between init_read polls, in seconds.",
    )
    parser.add_argument(
        "--post-config-delay",
        type=float,
        default=POST_CONFIG_DELAY,
        help="Delay after peripheral configuration before init commands, in seconds.",
    )
    parser.add_argument(
        "--run-idd",
        dest="run_idd",
        action="store_true",
        default=DEFAULT_RUN_IDD,
        help="Run IDD6 after init/RDC train and before GF.",
    )
    parser.add_argument(
        "--skip-idd",
        dest="run_idd",
        action="store_false",
        help="Do not run IDD6.",
    )
    parser.add_argument(
        "--run-gf",
        dest="run_gf",
        action="store_true",
        default=DEFAULT_RUN_GF,
        help="Run GF after init/RDC train. This is enabled by default.",
    )
    parser.add_argument(
        "--skip-gf",
        dest="run_gf",
        action="store_false",
        help="Do not run GF after init/RDC train.",
    )
    parser.add_argument(
        "--gf-repeat",
        "--repeat-gf",
        dest="gf_repeat",
        type=int,
        default=DEFAULT_GF_REPEAT,
        help="Number of GF start/read runs when GF is enabled.",
    )
    args = parser.parse_args()

    if args.gf_rdwr_gap is not None:
        args.gf_rd_gap = args.gf_rdwr_gap
        args.gf_wr_gap = args.gf_rdwr_gap

    global runtime_command_delay
    global runtime_init_first_read_delay
    global runtime_init_poll_interval
    runtime_command_delay = args.command_delay
    runtime_init_first_read_delay = args.init_first_read_delay
    runtime_init_poll_interval = args.init_poll_interval

    if not 0 <= args.read_capture_start <= 0xFF:
        raise ValueError("--read-capture-start must be 0..255")
    if not 0 <= args.rdc_train_dq_start <= 15:
        raise ValueError("--rdc-train-dq-start must be 0..15")
    if not 0 <= args.rdc_train_dq_end <= 15:
        raise ValueError("--rdc-train-dq-end must be 0..15")
    if args.rdc_train_dq_end < args.rdc_train_dq_start:
        raise ValueError("--rdc-train-dq-end must be >= --rdc-train-dq-start")
    if not 0 <= args.rdc_train_tap_start <= 0x1FF:
        raise ValueError("--rdc-train-tap-start must be 0..511")
    if not 0 <= args.rdc_train_tap_stop <= 0x1FF:
        raise ValueError("--rdc-train-tap-stop must be 0..511")
    if args.rdc_train_tap_stop < args.rdc_train_tap_start:
        raise ValueError("--rdc-train-tap-stop must be >= --rdc-train-tap-start")
    if args.rdc_train_tap_step <= 0 or args.rdc_train_tap_step > 0x1FF:
        raise ValueError("--rdc-train-tap-step must be 1..511")
    if args.rdc_train_timeout <= 0:
        raise ValueError("--rdc-train-timeout must be positive")
    if args.rdc_train_poll_interval < 0:
        raise ValueError("--rdc-train-poll-interval must be non-negative")
    if args.rdc_diagram_width <= 0:
        raise ValueError("--rdc-diagram-width must be positive")
    if args.command_delay < 0:
        raise ValueError("--command-delay must be non-negative")
    if args.init_first_read_delay < 0:
        raise ValueError("--init-first-read-delay must be non-negative")
    if args.init_poll_interval < 0:
        raise ValueError("--init-poll-interval must be non-negative")
    if args.post_config_delay < 0:
        raise ValueError("--post-config-delay must be non-negative")
    if args.gf_repeat <= 0:
        raise ValueError("--gf-repeat must be positive")
    dq_delay_override = any(getattr(args, f"dq{index}_delay") is not None for index in range(16))
    post_rdc_dq_delay_override = any(
        getattr(args, f"post_rdc_dq{index}_delay") is not None
        for index in range(16)
    )
    dq_delays = [
        getattr(args, f"dq{index}_delay")
        if getattr(args, f"dq{index}_delay") is not None
        else DEFAULT_DQ_DELAYS[index]
        for index in range(16)
    ]
    for index, delay in enumerate(dq_delays):
        if not 0 <= delay <= 0x1FF:
            raise ValueError(f"--dq{index}-delay must be 0..511")
    for index in range(16):
        delay = getattr(args, f"post_rdc_dq{index}_delay")
        if delay is not None and not 0 <= delay <= 0x1FF:
            raise ValueError(f"--post-rdc-dq{index}-delay must be 0..511")
    if not 0 <= args.gf_capture_start <= 0xFF:
        raise ValueError("--gf-capture-start must be 0..255")
    if not 0 <= args.init_beat_offset <= 8:
        raise ValueError("--init-beat-offset must be 0..8")
    if not 0 <= args.gf_beat_offset <= 8:
        raise ValueError("--gf-beat-offset must be 0..8")
    for name in (
        "rd_wck_start",
        "rd_wck_last",
        "wr_wck_start",
        "wr_wck_last",
        "gf_read_done_cnt",
        "gf_write_done_cnt",
    ):
        if not 0 <= getattr(args, name) <= 0x3FF:
            raise ValueError(f"--{name.replace('_', '-')} must be 0..1023")
    for name in (
        "gf_act_gap",
        "gf_rd_gap",
        "gf_wr_gap",
        "gf_pre_gap",
    ):
        if not 0 <= getattr(args, name) <= MAX_GF_STREAM_GAP:
            raise ValueError(
                f"--{name.replace('_', '-')} must be 0..{MAX_GF_STREAM_GAP}"
            )
    if args.gf_rdwr_gap is not None and not 0 <= args.gf_rdwr_gap <= MAX_GF_STREAM_GAP:
        raise ValueError(f"--gf-rdwr-gap must be 0..{MAX_GF_STREAM_GAP}")
    set_bar06_capture_cfg_command(
        args.read_capture_start,
        args.gf_capture_start,
        args.init_beat_offset,
        args.gf_beat_offset,
        args.rd_wck_start,
        args.rd_wck_last,
        args.wr_wck_start,
        args.wr_wck_last,
        args.gf_read_done_cnt,
        args.gf_write_done_cnt,
    )
    set_bar06_gf_stream_cfg_command(
        args.gf_act_gap,
        args.gf_rd_gap,
        args.gf_wr_gap,
        args.gf_pre_gap,
        args.gf_refresh_batch,
    )
    set_bar06_gf_pattern_cfg_command(args.gf_pattern_mode)
    if dq_delay_override:
        set_bar06_dq_delay_commands(dq_delays)
    set_bar06_rdc_train_config_command(
        args.rdc_train_dq_start,
        args.rdc_train_dq_end,
        args.rdc_train_tap_start,
        args.rdc_train_tap_stop,
        args.rdc_train_tap_step,
        not args.rdc_train_no_apply_best,
        args.rdc_train,
        args.rdc_train_dual_pattern,
    )
    config_sequence = list(CONFIG_SEQUENCE)
    config_sequence.insert(-1, "rdc_train_cfg")
    if dq_delay_override:
        config_sequence.insert(-1, "bar06_dq_delay_l")
        config_sequence.insert(-1, "bar06_dq_delay_h")

    total_start = time.monotonic()
    config_elapsed = 0.0
    init_elapsed = 0.0
    idd_elapsed = 0.0
    gf_elapsed = 0.0

    with serial.Serial(args.port, args.baudrate, timeout=SERIAL_TIMEOUT) as port:
        if not args.skip_config:
            config_elapsed = send_sequence(port, "Peripheral configuration", config_sequence)
            if args.post_config_delay > 0:
                print(f"post-config wait {args.post_config_delay:.2f}s\n")
                time.sleep(args.post_config_delay)

        print_capture_config_readback(port)
        print_gf_stream_config_readback(port)
        print_gf_pattern_config_readback(port)

        if args.config_only:
            return

        if args.gf_only:
            print("=== LP5 GF only ===")
            gf_start = time.monotonic()
            print_dq_delay_readback(port, "DQ delay readback before GF:")
            run_gf(port, args.no_poll, args.gf_repeat)
            print_dq_delay_readback(port, "DQ delay readback after GF:")
            gf_elapsed = time.monotonic() - gf_start
            print(f"LP5 GF elapsed: {gf_elapsed:.3f}s\n")
            return

        print("=== LP5 init / RDC ===")
        init_start = time.monotonic()
        run_init(port, args.no_poll, args.rdc_train)
        rdc_frame = send_command(port, "rdc_status")
        print_rdc_status(decode_rdc_status(rdc_frame))
        print()

        if args.rdc_train:
            print("=== BAR06 RDC train result ===")
            print(
                "rdc_train mode: "
                f"{'dual-pattern 5A/A5 + 3C/C3' if args.rdc_train_dual_pattern else 'single-pattern 5A/A5'}"
            )
            rdc_train_status = wait_rdc_train_done(
                port,
                args.rdc_train_timeout,
                args.rdc_train_poll_interval,
                args.rdc_train_verbose_poll,
            )
            best = read_9bit_flat16(port, "rdc_train_best_l", "rdc_train_best_h")
            left = read_9bit_flat16(port, "rdc_train_left_l", "rdc_train_left_h")
            right = read_9bit_flat16(port, "rdc_train_right_l", "rdc_train_right_h")
            diagram_start = (
                args.rdc_train_tap_start
                if args.rdc_diagram_start is None else args.rdc_diagram_start
            )
            diagram_stop = (
                args.rdc_train_tap_stop
                if args.rdc_diagram_stop is None else args.rdc_diagram_stop
            )
            if diagram_stop < diagram_start:
                raise ValueError("--rdc-diagram-stop must be >= --rdc-diagram-start")
            print_rdc_train_result(
                rdc_train_status,
                best,
                left,
                right,
                args.rdc_train_dq_start,
                args.rdc_train_dq_end,
                diagram_start,
                diagram_stop,
                args.rdc_diagram_width,
            )
            print()
            if args.rdc_print_scan:
                rdc_scan_map = read_rdc_train_scan_map(
                    port,
                    args.rdc_train_tap_start,
                    args.rdc_train_tap_stop,
                    args.rdc_train_tap_step,
                )
                print_rdc_train_scan_map(
                    rdc_scan_map,
                    args.rdc_train_dq_start,
                    args.rdc_train_dq_end,
                    args.rdc_train_tap_step,
                    args.rdc_diagram_width,
                )
                print()
            print_dq_delay_readback(port, "DQ delay readback after RDC train:")
            print()
            if rdc_train_status["pass_all"] != 1:
                raise RuntimeError(
                    "rdc_train failed; stop before GF because trained DQ delays are invalid"
                )

        if post_rdc_dq_delay_override:
            post_rdc_dq_delays = read_9bit_flat16(
                port,
                "bar06_dq_delay_l_read",
                "bar06_dq_delay_h_read",
            )
            for index in range(16):
                delay = getattr(args, f"post_rdc_dq{index}_delay")
                if delay is not None:
                    post_rdc_dq_delays[index] = delay
            set_bar06_dq_delay_commands(post_rdc_dq_delays)
            print("=== BAR06 post-RDC DQ delay override ===")
            send_command(port, "bar06_dq_delay_l")
            send_command(port, "bar06_dq_delay_h")
            print_dq_delay_readback(port, "DQ delay readback after post-RDC override:")
            print()

        for mrw_item in args.mrw:
            ma_text, op_text = mrw_item.split(":", 1)
            send_runtime_mrw(port, int(ma_text, 0), int(op_text, 0))

        if args.run_idd:
            print("=== LP5 IDD6 ===")
            idd_start = time.monotonic()
            run_idd6(port, args.no_poll)
            idd_elapsed = time.monotonic() - idd_start
            print(f"LP5 IDD6 elapsed: {idd_elapsed:.3f}s\n")

        if args.run_gf:
            print("=== LP5 GF ===")
            gf_start = time.monotonic()
            print_dq_delay_readback(port, "DQ delay readback before GF:")
            run_gf(port, args.no_poll, args.gf_repeat)
            print_dq_delay_readback(port, "DQ delay readback after GF:")
            gf_elapsed = time.monotonic() - gf_start
            print(f"LP5 GF elapsed: {gf_elapsed:.3f}s\n")

        init_elapsed = time.monotonic() - init_start
        print(f"LP5 init/RDC elapsed: {init_elapsed:.3f}s\n")

    total_elapsed = time.monotonic() - total_start
    print("=== Summary ===")
    print(f"config elapsed: {config_elapsed:.3f}s")
    print(f"init elapsed:   {init_elapsed:.3f}s")
    print(f"idd elapsed:    {idd_elapsed:.3f}s")
    print(f"gf elapsed:     {gf_elapsed:.3f}s")
    print(f"total elapsed:  {total_elapsed:.3f}s")


if __name__ == "__main__":
    main()
