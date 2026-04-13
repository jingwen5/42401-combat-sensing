# battery_test.py
import asyncio
import sys
import os
import csv
from datetime import datetime

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(CURRENT_DIR)
APP_DIR = os.path.join(PROJECT_ROOT, "app")
sys.path.insert(0, APP_DIR)
sys.path.insert(0, PROJECT_ROOT)

from ble_monitor import PacketParser, DEVICE_NAME, TX_CHAR_UUID
from utils.ble_runner import run_ble

LOG_FILE = "tests/data/battery_log_charge.csv"

parser = PacketParser()

def handle_notification(sender, data):
    for decoded in parser.feed(data):
        if decoded[0] == "B":
            _, ts, vbat = decoded
            now = datetime.now().isoformat(timespec="seconds")
            if vbat >= 3.5:
                # Linear region: 4.2V to 3.5V = 100% to 7%
                pct = int(7 + (vbat - 3.5) / (4.2 - 3.5) * 93)
            else:
                # Knee region: 3.5V to 2.5V = 7% to 0%
                pct = int((vbat - 2.5) / (3.5 - 2.5) * 7)

            pct = max(0, min(100, pct))

            print(f"[{now}] vbat={vbat:.2f}V ({pct}%)")
            with open(LOG_FILE, "a", newline="") as f:
                csv.writer(f).writerow([now, ts, vbat, pct])

async def main():
    # Write header if file doesn't exist
    if not os.path.exists(LOG_FILE):
        with open(LOG_FILE, "w", newline="") as f:
            csv.writer(f).writerow(["datetime", "device_ts", "vbat", "pct"])

    await run_ble(DEVICE_NAME, TX_CHAR_UUID, handle_notification)

if __name__ == "__main__":
    asyncio.run(main())