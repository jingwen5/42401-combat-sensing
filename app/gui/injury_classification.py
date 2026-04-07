from collections import deque

# store data buffers for derivative calculations, collect over a fixed window size
WINDOW_SIZE = 100

class InjuryClassifier:
    def __init__(self):
        self.hr_buf = deque(maxlen=WINDOW_SIZE)
        self.spo2_buf = deque(maxlen=WINDOW_SIZE)
        self.motion_buf = deque(maxlen=WINDOW_SIZE)
        self.rr_buf = deque(maxlen=WINDOW_SIZE)
        self.bp_buf = deque(maxlen=WINDOW_SIZE)

    def update(self, hr, spo2, rr, bp, motion_state):
        if hr is not None:
            self.hr_buf.append(hr)
        if spo2 is not None:
            self.spo2_buf.append(spo2)
        if rr is not None:
            self.rr_buf.append(rr)
        if bp is not None:
            self.bp_buf.append(bp)
        if motion_state is not None:
            self.motion_buf.append(motion_state)
            
    def calculate_injury_probabilities(self):
        