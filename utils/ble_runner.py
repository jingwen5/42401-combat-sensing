# ble_runner.py
# Connect to BLE on XIAO-SENSE

import asyncio
from bleak import BleakClient, BleakScanner

async def run_ble(device_name: str, char_uuid: str, on_notify, timeout: float = 15.0):
    print(f"Scanning for BLE device '{device_name}'...")
    device = await BleakScanner.find_device_by_name(device_name, timeout=timeout)

    if device is None:
        print("Device not found.")
        return

    print("Connecting...")
    async with BleakClient(device) as client:
        print("Connected.")
        await client.start_notify(char_uuid, on_notify)
        print("Streaming BLE... Ctrl+C to stop.\n")

        try:
            while True:
                await asyncio.sleep(1.0)
        except KeyboardInterrupt:
            print("\nStopping...")
        finally:
            await client.stop_notify(char_uuid)