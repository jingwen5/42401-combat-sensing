# ppg_stream.py
# Store PPG data into buffers

from collections import deque
from utils.ble_packets import PacketParser

class PPGStream:
    def __init__(self, maxlen=5000):
        self.parser = PacketParser()
        self.ir = deque(maxlen=maxlen)
        self.red = deque(maxlen=maxlen)
        self.ts = deque(maxlen=maxlen)

    def feed(self, data: bytes):
        for pkt in self.parser.feed(data):
            if pkt[0] == "P":
                _, ts_us, ir, red = pkt
                self.ts.append(ts_us)
                self.ir.append(ir)
                self.red.append(red)
                yield (ts_us, ir, red)