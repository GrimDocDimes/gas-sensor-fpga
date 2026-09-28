"""
read_a0.py  –  Read the Arduino A0 analog pin on PYNQ-Z2
==========================================================

Circuit
-------
  3.3V ──[10kΩ]──┬──[10kΩ]── GND
                 │
                A0  (Arduino header, XADC channel vaux1)

Expected reading:  ~1.65 V  (mid-point of voltage divider)

Run on the PYNQ-Z2 board:
    $ python3 read_a0.py

Or inside a Jupyter notebook cell:
    %run read_a0.py
"""

import time
from pynq import Overlay
from pynq.lib.arduino import Arduino_Analog

# ── 1. Load the base overlay (ships with PYNQ, always available) ──────────────
print("Loading base overlay …")
ol = Overlay("base.bit")        # /usr/local/lib/python3.8/dist-packages/pynq/overlays/base/base.bit
print("Overlay loaded.")

# ── 2. Instantiate the analog driver on the Arduino header ───────────────────
#
#  Arduino_Analog pins:
#    index 0  →  A0    (XADC, vaux1  / VP/VN on header)
#    index 1  →  A1
#    …up to A5
#
analog = Arduino_Analog(ol.iop_arduino.mb_info, [0])   # read A0 only

# ── 3. Read loop ──────────────────────────────────────────────────────────────
NUM_SAMPLES   = 20
DELAY_SECONDS = 0.5

print(f"\nReading A0 every {DELAY_SECONDS}s  ({NUM_SAMPLES} samples)\n")
print(f"{'Sample':>7}  {'Voltage (V)':>12}  {'Raw ADC (0-65535)':>18}")
print("-" * 44)

readings = []

for i in range(NUM_SAMPLES):
    # read_raw()  → list of raw 16-bit values (one per channel requested)
    # read()      → list of voltages in volts
    voltage = analog.read()[0]          # index 0 = A0
    raw     = analog.read_raw()[0]

    readings.append(voltage)
    print(f"{i+1:>7}  {voltage:>12.4f}  {raw:>18d}")
    time.sleep(DELAY_SECONDS)

# ── 4. Summary ────────────────────────────────────────────────────────────────
avg = sum(readings) / len(readings)
print("-" * 44)
print(f"\nAverage voltage : {avg:.4f} V")
print(f"Expected        : ~1.6500 V  (3.3V / 2, equal resistors)")
print(f"Deviation       : {abs(avg - 1.65)*1000:.1f} mV")
