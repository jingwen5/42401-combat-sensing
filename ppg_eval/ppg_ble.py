# ppg_ble.py
# Collect live HR/SpO2 estimates over BLE and save reference readings

import os
import sys
import csv
import time
import asyncio
import threading
from datetime import datetime

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(CURRENT_DIR)
sys.path.insert(0, PROJECT_ROOT)

from utils.ble_runner import run_ble
from utils.ble_packets import PacketParser

TX_CHAR_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
DEVICE_NAME = "XIAO-SENSE"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True)

EST_OUTPUT_FILE = os.path.join(DATA_DIR, "eval_est_loc_a.csv")  # Estimated HR/SpO2 from BLE
REF_OUTPUT_FILE = os.path.join(DATA_DIR, "eval_ref_loc_a.csv")  # Reference HR/SpO2 from fingertip

WINDOW = 10.0  # Seconds per window

# (activity label, duration in seconds)
# 7-minute protocol adapted from:
# Lin et al., "A Novel Chest-Based PPG Measurement System," IEEE JTEHM, 2024
# https://pmc.ncbi.nlm.nih.gov/articles/PMC11573410/
PROTOCOL_STEPS = [
    ("Normal breath", 60),
    ("Deep breath", 30),
    ("Normal breath", 60),
    ("Hold breath", 30),
    ("Normal breath", 60),
    ("Finger tap", 30),
    ("Normal breath", 60),
    ("Swing arm", 30),
    ("Normal breath", 60),
]

def now_iso():
    return datetime.now().isoformat(timespec="milliseconds")  # Timestamp string

def build_window_protocol(protocol_steps, window_sec):
    labels = []
    for label, duration in protocol_steps:
        labels += [label] * int(round(duration / window_sec))  # One label per window
    return labels

WINDOW_LABELS = build_window_protocol(PROTOCOL_STEPS, WINDOW)
SETS = len(WINDOW_LABELS)

def get_first_reference(window_num, label):
    print(f"\nWindow {window_num}: {label}")
    print("Enter HR SpO2 (e.g. 72 98)")

    while True:
        parts = input("> ").strip().split()
        if len(parts) != 2:
            continue
        try:
            return [now_iso(), window_num, float(parts[0]), float(parts[1])]
        except:
            continue

def input_thread(stop_event, window_num, ref_rows):
    # Allow additional reference entries during window
    while not stop_event.is_set():
        try:
            parts = input("Extra > ").strip().split()
        except EOFError:
            break

        if len(parts) != 2:
            continue

        try:
            ref_rows.append([
                now_iso(),
                window_num,
                float(parts[0]),
                float(parts[1])
            ])
        except:
            continue

class LivePPGCollector:
    def __init__(self, est_writer):
        self.est_writer = est_writer
        self.parser = PacketParser()

        self.window_num = None
        self.window_start_time = None
        self.window_done_event = None

        self.t0 = None  # First timestamp reference
        self.latest_result = None

    def start_window(self, window_num, done_event):
        self.window_num = window_num
        self.window_start_time = time.time()
        self.window_done_event = done_event
        self.latest_result = None

    def stop_window(self):
        self.window_num = None
        self.window_start_time = None
        self.window_done_event = None

    def handle_notification(self, sender: int, data: bytearray):
        # Decode BLE packets
        for decoded in self.parser.feed(data):
            ptype = decoded[0]

            if ptype != "R":
                continue  # Ignore non-result packets

            _, ts, hr, spo2 = decoded

            if self.t0 is None:
                self.t0 = ts  # Set time reference

            ts_rel = ts - self.t0  # Relative time

            hr_str = "---" if (hr is None or hr <= 0) else f"{hr:.2f}"
            spo2_str = "---" if (spo2 is None or spo2 <= 0) else f"{spo2:.2f}"

            print(f"[BLE RX] t={ts_rel}s hr={hr_str} bpm spo2={spo2_str} %")

            if self.window_num is None:
                continue  # Not currently recording a window

            # Save estimated values
            self.est_writer.writerow([
                now_iso(),
                self.window_num,
                ts_rel,
                hr,
                spo2
            ])

            self.latest_result = (hr, spo2)

            # Mark that result received for this window
            if self.window_done_event is not None:
                self.window_done_event.set()

async def run_window(window_num, label, collector, ref_writer):
    print("\n" + "=" * 50)
    print(f"Window {window_num}/{SETS}")
    print(f"Activity: {label}")

    ref_rows = [get_first_reference(window_num, label)]

    stop_event = threading.Event()
    threading.Thread(
        target=input_thread,
        args=(stop_event, window_num, ref_rows),
        daemon=True
    ).start()

    result_event = asyncio.Event()
    collector.start_window(window_num, result_event)

    start = time.time()

    # Wait for BLE result or timeout
    while time.time() - start < WINDOW:
        if result_event.is_set():
            break
        await asyncio.sleep(0.05)

    stop_event.set()
    collector.stop_window()

    # Save reference values
    for row in ref_rows:
        ref_writer.writerow(row)

    if collector.latest_result is not None:
        hr, spo2 = collector.latest_result
        print(f"Saved estimate: HR={hr:.2f}, SpO2={spo2:.2f}")
    else:
        print("No BLE result received")

    print(f"Saved {len(ref_rows)} reference readings")

async def main():
    print("Loaded protocol:")
    for i, label in enumerate(WINDOW_LABELS, start=1):
        print(f"  Window {i:2d}: {label}")
    print()

    with open(EST_OUTPUT_FILE, "w", newline="") as est_f, \
         open(REF_OUTPUT_FILE, "w", newline="") as ref_f:

        est_writer = csv.writer(est_f)
        ref_writer = csv.writer(ref_f)

        # CSV headers
        est_writer.writerow(["timestamp", "window", "ts_rel_s", "estimated_hr", "estimated_spo2"])
        ref_writer.writerow(["timestamp", "window", "true_hr", "true_spo2"])

        collector = LivePPGCollector(est_writer)

        # Start BLE listener
        ble_task = asyncio.create_task(
            run_ble(DEVICE_NAME, TX_CHAR_UUID, collector.handle_notification)
        )

        try:
            await asyncio.sleep(2.0)  # Allow BLE to connect

            for i, label in enumerate(WINDOW_LABELS):
                await run_window(i + 1, label, collector, ref_writer)

                est_f.flush()
                ref_f.flush()

        finally:
            ble_task.cancel()
            try:
                await ble_task
            except asyncio.CancelledError:
                pass

    print("\nDone.")

if __name__ == "__main__":
    asyncio.run(main())