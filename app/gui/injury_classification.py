from collections import deque

# store data buffers for derivative calculations, collect over a fixed window size
WINDOW_SIZE = 100

# constants for each buffer type
HR_BUF_TAG = 0
SPO2_BUF_TAG = 1
RR_BUF_TAG = 2
SP_BUF_TAG = 3
DP_BUF_TAG = 4
MOTION_BUF_TAG = 5

class InjuryClassifier:
    def __init__(self):
        # buffers for most recent data
        self.hr_buf = deque(maxlen=WINDOW_SIZE)
        self.spo2_buf = deque(maxlen=WINDOW_SIZE)
        self.motion_buf = deque(maxlen=WINDOW_SIZE)
        self.rr_buf = deque(maxlen=WINDOW_SIZE)
        self.sp_buf = deque(maxlen=WINDOW_SIZE)
        self.dp_buf = deque(maxlen=WINDOW_SIZE)
        self.shock_index_buf = deque(maxlen=WINDOW_SIZE)

        # probabilities of various injury
        self.hemorrhage = 0
        self.hemorrhage_bv_loss_lo = 0
        self.hemorrhage_by_loss_hi = 0
        self.hemothorax = 0
        self.pneumothorax = 0
        self.injured_limb = 0
        self.high_blast = 0

    def update(self, hr, spo2, rr, sp, dp, motion_state):
        # add samples to right end of queue (dequeue older samples)
        if hr is not None:
            self.hr_buf.append(hr)
        if spo2 is not None:
            self.spo2_buf.append(spo2)
        if rr is not None:
            self.rr_buf.append(rr)
        if sp is not None:
            self.sp_buf.append(sp)
        if dp is not None:
            self.sp_buf.append(dp)
        if motion_state is not None:
            self.motion_buf.append(motion_state)
        
        # calculate shock index = heart rate / systolic blood pressure
        if (sp is not None) and (sp != 0) and (hr is not None):
            self.shock_index_buf.append(sp / hr)
        
    # calculate averages over windows at specified parts of the buffer
    def calculate_average(self, start_idx, end_idx, buffer_tag):
        match buffer_tag:
            case 0: buf = self.hr_buf
            case 1: buf = self.spo2_buf
            case 2: buf = self.rr_buf
            case 3: buf = self.sp_buf
            case 4: buf = self.dp_buf
            case 5: buf = self.motion_buf
            case _: raise ValueError(f"Unknown buffer_tag: {buffer_tag}")

        # valid_samples = len(self.motion_buf) if (buffer_tag == MOTION_BUF_TAG) else len(self.hr_buf)        
        
        # not enough valid data in the buffer
        if(len(buf) < end_idx):
            return None

        curr_sum = sum(buf[i] for i in range(start_idx, end_idx))
        
        return (curr_sum / (end_idx - start_idx))
            
    # calculate probability of hemorrhage and 
    # likely blood volume loss, return tuple (hemorrhage_probability, bv_loss_lo, bv_loss_hi)
    def calculate_hemorrhage(self):
        bv_loss_lo = 0
        bv_loss_hi = 0
        hh_prob = 0

        avg_hr = self.calculate_average(0, WINDOW_SIZE, HR_BUF_TAG)
        avg_sp = self.calculate_average(0, WINDOW_SIZE, SP_BUF_TAG)
        avg_dp = self.calculate_average(0, WINDOW_SIZE, DP_BUF_TAG)
        avg_rr = self.calculate_average(0, WINDOW_SIZE, RR_BUF_TAG)
        
        if((avg_hr is None) or (avg_sp is None) or (avg_dp is None) or (avg_rr is None)):
            return None
        
        
        
        if((avg_hr < 100) and ((avg_rr >= 14) and (avg_rr < 20))):
            bv_loss_lo = 0
            bv_loss_hi = 15
            hh_prob = 0.05
        elif((avg_hr >= 100) and (avg_hr < 120) and (avg_rr >= 20) and (avg_rr < 30)):
            bv_loss_lo = 15
            bv_loss_hi = 30
            hh_prob = 0.55
        elif((avg_hr >= 120) and (avg_hr < 140) and (avg_rr >= 30) and (avg_rr < 40)):
            bv_loss_lo = 30
            bv_loss_hi = 40
            hh_prob = 0.8
        elif((avg_hr >= 140) and (avg_rr >= 30) and (avg_rr < 40)):
            bv_loss_lo = 40
            bv_loss_hi = 100
            hh_prob = 0.95
        
        self.hemorrhage = hh_prob
        self.hemorrhage_bv_loss_lo = bv_loss_lo
        self.hemorrhage_by_loss_hi = bv_loss_hi
            
        return (hh_prob, bv_loss_lo, bv_loss_hi)
    
    # calculate probability of hemothorax
    def calculate_hemothorax(self):
        pass
    
    # calculate probability of pneumothorax
    def calculate_pneumothorax(self):
        pass
    
    # calculate probability of a limb injury (fracture,
    # gunshot wound) or explosive blast injury
    def calculate_limb_and_blast_injury(self):
        pass
    
    # main fn to update all injury probabilities
    def calculate_injury_probabilities(self):
        self.calculate_hemorrhage()
        self.calculate_hemothorax()
        self.calculate_limb_and_blast_injury()
        self.calculate_pneumothorax()