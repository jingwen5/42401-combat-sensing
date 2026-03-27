# ble_packets.py
# BLE binary packet parser for XIAO-SENSE.

import struct

PACKET_LEN = 9

class PacketParser:
    def __init__(self, packet_len: int = PACKET_LEN):
        self.packet_len = packet_len
        self.buf = bytearray()

    def feed(self, data: bytes):
        """Feed raw notification bytes. Yields decoded packets."""
        self.buf.extend(data)

        while len(self.buf) >= self.packet_len:
            pkt = self.buf[:self.packet_len]
            del self.buf[:self.packet_len]

            ptype = pkt[0]

            if ptype == ord('R'):
                # ts(uint32) + hr(int16 x100) + spo2(int16 x100)
                ts_ms, hr_i, spo2_i = struct.unpack_from("<Ihh", pkt, 1)

                hr = None if hr_i == -1 else hr_i / 100.0
                spo2 = None if spo2_i == -1 else spo2_i / 100.0

                yield ("R", ts_ms, hr, spo2)

            else:
                yield ("?", pkt)