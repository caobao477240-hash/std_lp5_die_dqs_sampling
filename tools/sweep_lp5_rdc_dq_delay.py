"""Sweep LP5 RDC per-DQ input delay taps by rerunning full init.

Example:
    python tools/sweep_lp5_rdc_dq_delay.py --port COM4 --dq-list 0,1,2,4,6,7 --tap-start 8 --tap-stop 40 --tap-step 4
"""

import argparse
import csv
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from run_lp5_debug import DEFAULT_BAUDRATE, DEFAULT_DQ_DELAYS, DEFAULT_PORT


RDC_RE = re.compile(
    r"rdc_status:\s+valid=(?P<valid>[01])\s+pass=(?P<passed>[01])\s+err_bitmap=0x(?P<err>[0-9a-fA-F]+)"
)


def parse_int(text):
    return int(text, 0)


def parse_list(text):
    if text.lower() == "all":
        return list(range(16))
    values = []
    for part in text.split(","):
        item = part.strip()
        if not item:
            continue
        if "-" in item:
            left, right = item.split("-", 1)
            values.extend(range(parse_int(left), parse_int(right) + 1))
        else:
            values.append(parse_int(item))
    for value in values:
        if value < 0 or value > 15:
            raise ValueError("--dq-list values must be 0..15")
    return values


def parse_delay_list(text):
    values = [parse_int(item.strip()) for item in text.split(",") if item.strip()]
    if len(values) != 16:
        raise ValueError("--base-delays needs 16 comma-separated values")
    for index, value in enumerate(values):
        if value < 0 or value > 0x1FF:
            raise ValueError(f"DQ{index} base delay must be 0..511")
    return values


def make_taps(args):
    if args.tap_list:
        taps = [parse_int(item.strip()) for item in args.tap_list.split(",") if item.strip()]
    else:
        if args.tap_step <= 0:
            raise ValueError("--tap-step must be positive")
        taps = list(range(args.tap_start, args.tap_stop + 1, args.tap_step))
    for tap in taps:
        if tap < 0 or tap > 0x1FF:
            raise ValueError("tap values must be 0..511")
    return taps


def run_one(args, delays, log_path):
    script_path = Path(__file__).with_name("run_lp5_debug.py")
    cmd = [
        sys.executable,
        str(script_path),
        "--port",
        args.port,
        "--baudrate",
        str(args.baudrate),
        "--read-capture-start",
        hex(args.read_capture_start),
        "--no-rdc-train",
        "--skip-gf",
    ]
    for index, delay in enumerate(delays):
        cmd.extend([f"--dq{index}-delay", hex(delay)])

    start = time.monotonic()
    proc = subprocess.run(
        cmd,
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=args.timeout,
    )
    elapsed = time.monotonic() - start
    log_path.write_text(proc.stdout + proc.stderr, encoding="utf-8", errors="replace")

    match = RDC_RE.search(proc.stdout)
    valid = passed = None
    err_bitmap = None
    if match:
        valid = int(match.group("valid"))
        passed = int(match.group("passed"))
        err_bitmap = int(match.group("err"), 16)

    return {
        "returncode": proc.returncode,
        "elapsed_s": elapsed,
        "valid": valid,
        "passed": passed,
        "err_bitmap": err_bitmap,
        "cmd": " ".join(cmd),
    }


def bit_is_clear(value, index):
    if value is None:
        return False
    return ((value >> index) & 1) == 0


def popcount(value):
    if value is None:
        return 999
    return value.bit_count()


def select_best_for_dq(rows, dq, base_tap, step):
    sorted_rows = sorted(rows, key=lambda row: row["tap"])
    ok_rows = [
        row for row in sorted_rows
        if row["valid"] == 1 and row["returncode"] == 0 and bit_is_clear(row["err_bitmap"], dq)
    ]

    runs = []
    cur_run = []
    prev_tap = None
    for row in ok_rows:
        if prev_tap is None or row["tap"] == prev_tap + step:
            cur_run.append(row)
        else:
            runs.append(cur_run)
            cur_run = [row]
        prev_tap = row["tap"]
    if cur_run:
        runs.append(cur_run)

    if runs:
        runs.sort(
            key=lambda run: (
                len(run),
                -min(popcount(row["err_bitmap"]) for row in run),
                -min(abs(row["tap"] - base_tap) for row in run),
            ),
            reverse=True,
        )
        best_run = runs[0]
        best_row = best_run[len(best_run) // 2]
        return best_row, best_run

    valid_rows = [row for row in sorted_rows if row["valid"] == 1 and row["returncode"] == 0]
    if valid_rows:
        valid_rows.sort(
            key=lambda row: (
                ((row["err_bitmap"] >> dq) & 1),
                popcount(row["err_bitmap"]),
                abs(row["tap"] - base_tap),
            )
        )
        return valid_rows[0], []

    if sorted_rows:
        sorted_rows.sort(key=lambda row: (row["returncode"] != 0, abs(row["tap"] - base_tap)))
        return sorted_rows[0], []

    return None, []


def row_to_csv(row):
    data = dict(row)
    err_bitmap = data.get("err_bitmap")
    data["err_bitmap"] = "" if err_bitmap is None else f"0x{err_bitmap:04X}"
    data["delays"] = ",".join(str(value) for value in data["delays"])
    data["elapsed_s"] = f"{data['elapsed_s']:.3f}"
    return data


def build_window_diagram(rows, dq_list, tap_values, selection_by_dq):
    lines = []
    lines.append("")
    lines.append("RDC sampled window diagram:")
    lines.append("  legend: '=' target DQ ok, '.' target DQ fail, '?' invalid/no response, 'B' selected tap")
    lines.append("  tap_values: " + ",".join(str(tap) for tap in tap_values))
    lines.append("              " + "".join(f"{tap % 10}" for tap in tap_values))

    for dq in dq_list:
        dq_rows = [
            row for row in rows
            if row["kind"] == "scan" and row["scan_dq"] == dq
        ]
        row_by_tap = {row["tap"]: row for row in dq_rows}
        best_row, best_run = selection_by_dq.get(dq, (None, []))
        selected_tap = None if best_row is None else best_row["tap"]
        run_text = "no clean window"

        if best_run:
            run_taps = [row["tap"] for row in best_run]
            run_text = f"window={run_taps[0]}..{run_taps[-1]} points={len(run_taps)}"

        chars = []
        for tap in tap_values:
            row = row_by_tap.get(tap)
            if selected_tap == tap:
                chars.append("B")
            elif row is None:
                chars.append("?")
            elif row["valid"] != 1 or row["returncode"] != 0:
                chars.append("?")
            elif bit_is_clear(row["err_bitmap"], dq):
                chars.append("=")
            else:
                chars.append(".")

        if selected_tap is None:
            select_text = "select=----"
        else:
            select_text = f"select={selected_tap}"
        lines.append(f"  DQ{dq:02d}:      {''.join(chars)}  {select_text} {run_text}")

    return lines


def main():
    parser = argparse.ArgumentParser(description="Sweep LP5 RDC DQ IDELAY taps with full init at each point.")
    parser.add_argument("--port", default=DEFAULT_PORT)
    parser.add_argument("--baudrate", type=int, default=DEFAULT_BAUDRATE)
    parser.add_argument("--dq-list", default="0,1,2,4,6,7", help="DQ list, ranges, or all.")
    parser.add_argument("--tap-start", type=parse_int, default=8)
    parser.add_argument("--tap-stop", type=parse_int, default=40)
    parser.add_argument("--tap-step", type=parse_int, default=4)
    parser.add_argument("--tap-list", help="Explicit comma-separated tap list.")
    parser.add_argument("--read-capture-start", type=parse_int, default=0x10)
    parser.add_argument("--cnt-meas-read", type=parse_int, default=0x18)
    parser.add_argument(
        "--base-delays",
        default=",".join(str(value) for value in DEFAULT_DQ_DELAYS),
        help="16 comma-separated base DQ delays.",
    )
    parser.add_argument("--timeout", type=float, default=240.0)
    parser.add_argument("--log-dir", default="imp/bit")
    parser.add_argument("--no-combined", action="store_true", help="Do not run the combined best-tap check.")
    parser.add_argument("--combined-repeat", type=int, default=1)
    args = parser.parse_args()

    dq_list = parse_list(args.dq_list)
    tap_values = make_taps(args)
    base_delays = parse_delay_list(args.base_delays)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.log_dir) / f"rdc_delay_scan_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "results.csv"
    summary_path = out_dir / "summary.txt"

    rows = []
    print(f"RDC delay scan output: {out_dir}")
    print(f"base delays: {base_delays}")
    print(f"read_capture_start=0x{args.read_capture_start:02X}")
    print(f"dq_list={dq_list} taps={tap_values}")

    for dq in dq_list:
        for tap in tap_values:
            delays = list(base_delays)
            delays[dq] = tap
            log_path = out_dir / f"dq{dq:02d}_tap{tap:03d}.log"
            print(f"[scan] DQ{dq:02d} tap={tap:03d}", flush=True)
            try:
                result = run_one(args, delays, log_path)
            except subprocess.TimeoutExpired:
                result = {
                    "returncode": -1,
                    "elapsed_s": args.timeout,
                    "valid": None,
                    "passed": None,
                    "err_bitmap": None,
                    "cmd": "timeout",
                }
                log_path.write_text("TIMEOUT\n", encoding="utf-8")

            row = {
                "kind": "scan",
                "scan_dq": dq,
                "tap": tap,
                "target_ok": int(bit_is_clear(result["err_bitmap"], dq)),
                "returncode": result["returncode"],
                "valid": result["valid"],
                "passed": result["passed"],
                "err_bitmap": result["err_bitmap"],
                "err_count": popcount(result["err_bitmap"]),
                "elapsed_s": result["elapsed_s"],
                "delays": delays,
                "log_path": str(log_path),
                "cmd": result["cmd"],
            }
            rows.append(row)
            err_text = "----" if row["err_bitmap"] is None else f"0x{row['err_bitmap']:04X}"
            print(
                f"       valid={row['valid']} pass={row['passed']} err={err_text} "
                f"target_ok={row['target_ok']} elapsed={row['elapsed_s']:.1f}s",
                flush=True,
            )

    selected = list(base_delays)
    summary_lines = []
    summary_lines.append(f"csv: {csv_path}")
    summary_lines.append(f"read_capture_start: 0x{args.read_capture_start:02X}")
    summary_lines.append(f"base_delays: {base_delays}")
    summary_lines.append(f"tap_values: {tap_values}")
    summary_lines.append("")
    summary_lines.append("Per-DQ selection:")
    selection_by_dq = {}
    for dq in dq_list:
        dq_rows = [row for row in rows if row["kind"] == "scan" and row["scan_dq"] == dq]
        best_row, best_run = select_best_for_dq(dq_rows, dq, base_delays[dq], args.tap_step)
        selection_by_dq[dq] = (best_row, best_run)
        if best_row is None:
            selected[dq] = base_delays[dq]
            summary_lines.append(f"  DQ{dq:02d}: no result, keep {base_delays[dq]}")
            continue
        selected[dq] = best_row["tap"]
        if best_run:
            run_taps = [row["tap"] for row in best_run]
            summary_lines.append(
                f"  DQ{dq:02d}: select {best_row['tap']} from ok window "
                f"{run_taps[0]}..{run_taps[-1]} ({len(run_taps)} points)"
            )
        else:
            err_text = "----" if best_row["err_bitmap"] is None else f"0x{best_row['err_bitmap']:04X}"
            summary_lines.append(
                f"  DQ{dq:02d}: select {best_row['tap']} no clean window, "
                f"best err={err_text}"
            )

    summary_lines.append("")
    summary_lines.append("selected_delays: " + ",".join(str(value) for value in selected))
    summary_lines.extend(build_window_diagram(rows, dq_list, tap_values, selection_by_dq))
    print()
    print("\n".join(summary_lines))

    if not args.no_combined:
        for repeat_index in range(args.combined_repeat):
            log_path = out_dir / f"combined_{repeat_index}.log"
            print(f"[combined] repeat={repeat_index} delays={selected}", flush=True)
            try:
                result = run_one(args, selected, log_path)
            except subprocess.TimeoutExpired:
                result = {
                    "returncode": -1,
                    "elapsed_s": args.timeout,
                    "valid": None,
                    "passed": None,
                    "err_bitmap": None,
                    "cmd": "timeout",
                }
                log_path.write_text("TIMEOUT\n", encoding="utf-8")
            row = {
                "kind": "combined",
                "scan_dq": "",
                "tap": "",
                "target_ok": "",
                "returncode": result["returncode"],
                "valid": result["valid"],
                "passed": result["passed"],
                "err_bitmap": result["err_bitmap"],
                "err_count": popcount(result["err_bitmap"]),
                "elapsed_s": result["elapsed_s"],
                "delays": selected,
                "log_path": str(log_path),
                "cmd": result["cmd"],
            }
            rows.append(row)
            err_text = "----" if row["err_bitmap"] is None else f"0x{row['err_bitmap']:04X}"
            line = (
                f"combined repeat {repeat_index}: valid={row['valid']} "
                f"pass={row['passed']} err={err_text}"
            )
            summary_lines.append(line)
            print(line, flush=True)

    fieldnames = [
        "kind",
        "scan_dq",
        "tap",
        "target_ok",
        "returncode",
        "valid",
        "passed",
        "err_bitmap",
        "err_count",
        "elapsed_s",
        "delays",
        "log_path",
        "cmd",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row_to_csv(row))

    summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    print()
    print(f"wrote {csv_path}")
    print(f"wrote {summary_path}")


if __name__ == "__main__":
    main()
