#!/usr/bin/env python3
"""
Gas Sensing System — Real-Time UART Logger
==========================================
Reads ASCII frames from the FPGA over USB-UART (115200 baud) and logs them
to a timestamped CSV file.

Frame format expected from FPGA:
    NNNNNN,RGAS,RAIR,DDDDD,SSSSS\r\n

Output CSV columns:
    timestamp_unix, sample_count, r_gas, r_air, delta, sensitivity_x100

Usage:
    python3 gas_logger.py                        # Auto-detect port
    python3 gas_logger.py --port /dev/ttyUSB1   # Specify port
    python3 gas_logger.py --output my_run.csv   # Custom output file
    python3 gas_logger.py --port COM3 --output run1.csv  # Windows
"""

import argparse
import csv
import glob
import os
import sys
import time
from datetime import datetime

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Port auto-detection
# ---------------------------------------------------------------------------
def find_port() -> str:
    """Try to auto-detect a USB-UART port (FT2232H / Nexys 4 DDR)."""
    candidates = []

    # Linux: /dev/ttyUSB* or /dev/ttyACM*
    for pattern in ["/dev/ttyUSB*", "/dev/ttyACM*"]:
        candidates.extend(glob.glob(pattern))

    # Windows: COM ports
    ports = serial.tools.list_ports.comports()
    for p in ports:
        if "FTDI" in (p.manufacturer or "") or "USB Serial" in (p.description or ""):
            candidates.insert(0, p.device)

    if not candidates:
        print("ERROR: No USB-UART port found. Specify with --port.")
        sys.exit(1)

    if len(candidates) > 1:
        print(f"Multiple ports found: {candidates}")
        print(f"Using first: {candidates[0]} (use --port to override)")

    return candidates[0]


# ---------------------------------------------------------------------------
# Frame parsing
# ---------------------------------------------------------------------------
def parse_frame(line: str):
    """
    Parse a frame string into a dict.
    Expected: "NNNNNN,RGAS,RAIR,DDDDD,SSSSS"
    Returns dict or None on parse error.
    """
    parts = line.strip().split(",")
    if len(parts) != 5:
        return None
    try:
        return {
            "sample_count":     int(parts[0]),
            "r_gas":            int(parts[1]),
            "r_air":            int(parts[2]),
            "delta":            int(parts[3]),
            "sensitivity_x100": int(parts[4]),
        }
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Main logger loop
# ---------------------------------------------------------------------------
def run_logger(port: str, output: str, baud: int = 115200):
    print(f"Opening {port} at {baud} baud...")
    print(f"Logging to: {output}")
    print("Press Ctrl+C to stop.\n")

    fieldnames = [
        "timestamp_unix",
        "datetime_utc",
        "sample_count",
        "r_gas",
        "r_air",
        "delta",
        "sensitivity_x100",
        "sensitivity_pct",
    ]

    file_exists = os.path.exists(output)

    with serial.Serial(port, baud, timeout=2) as ser, \
         open(output, "a", newline="") as csvfile:

        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        if not file_exists:
            writer.writeheader()
            csvfile.flush()

        frame_count = 0
        error_count = 0
        t_start = time.time()

        try:
            while True:
                raw = ser.readline()
                if not raw:
                    continue  # Timeout — keep waiting

                try:
                    line = raw.decode("ascii", errors="ignore").strip()
                except Exception:
                    continue

                if not line:
                    continue

                frame = parse_frame(line)
                if frame is None:
                    error_count += 1
                    if error_count <= 5:
                        print(f"  [warn] Unparseable frame: {repr(line)}")
                    continue

                ts = time.time()
                dt = datetime.utcfromtimestamp(ts).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
                frame["timestamp_unix"] = ts
                frame["datetime_utc"]   = dt
                frame["sensitivity_pct"] = frame["sensitivity_x100"] / 100.0

                writer.writerow(frame)
                csvfile.flush()
                frame_count += 1

                # Pretty terminal output
                sign = "+" if frame["delta"] >= 0 else ""
                sens = frame["sensitivity_x100"] / 100.0
                print(
                    f"[{frame['sample_count']:>6}]  "
                    f"R_gas={frame['r_gas']:>4}  R_air={frame['r_air']:>4}  "
                    f"ΔR={sign}{frame['delta']:>5}  "
                    f"Sens={sens:+.2f}%"
                )

        except KeyboardInterrupt:
            elapsed = time.time() - t_start
            print(f"\nStopped. {frame_count} frames logged in {elapsed:.1f}s "
                  f"({frame_count/elapsed:.1f} fps). Errors: {error_count}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Gas sensor UART logger")
    parser.add_argument("--port",   default=None, help="Serial port (e.g. /dev/ttyUSB1)")
    parser.add_argument("--baud",   default=115200, type=int, help="Baud rate (default 115200)")
    parser.add_argument("--output", default="gas_log.csv", help="Output CSV file")
    args = parser.parse_args()

    port = args.port or find_port()
    run_logger(port, args.output, args.baud)


if __name__ == "__main__":
    main()
