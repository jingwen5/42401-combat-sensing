import tkinter as tk
import random
import time

# CONFIGURATION (COMBAT TRIAGE)
UPDATE_INTERVAL = 1000
IMMOBILE_CRITICAL = 10        # seconds
IMMOBILE_UNRESPONSIVE = 60    # seconds

# MAIN
class TriageGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Soldier Triage Monitor")
        self.root.geometry("440x720")
        self.root.configure(bg="#121212")

        self.last_motion_time = time.time()
        self.fall_detected = False
        self.data_link_status = "ACTIVE"

        self.build_ui()
        self.update_data()

    # UI
    def build_ui(self):
        tk.Label(
            self.root,
            text="SOLDIER ID: A-17",
            font=("Helvetica", 18, "bold"),
            fg="white",
            bg="#121212"
        ).pack(pady=10)

        self.status_label = tk.Label(
            self.root,
            text="STATUS: STABLE",
            font=("Helvetica", 26, "bold"),
            fg="lime",
            bg="#121212"
        )
        self.status_label.pack(pady=10)

        self.hr_label, self.hr_flag = self.create_metric("HEART RATE", "BPM")
        self.spo2_label, self.spo2_flag = self.create_metric("SpO2", "%")
        self.bp_label, self.bp_flag = self.create_metric("BLOOD PRESSURE", "mmHg")

        self.fall_label = tk.Label(
            self.root,
            text="FALL STATUS: NO FALL DETECTED",
            font=("Helvetica", 16),
            fg="lime",
            bg="#121212"
        )
        self.fall_label.pack(pady=10)

        self.immobile_label = tk.Label(
            self.root,
            text="IMMOBILE TIME: 0 s",
            font=("Helvetica", 18, "bold"),
            fg="white",
            bg="#121212"
        )
        self.immobile_label.pack(pady=5)

        self.data_link_label = tk.Label(
            self.root,
            text="DATA LINK: ACTIVE",
            font=("Helvetica", 14, "bold"),
            fg="lime",
            bg="#121212"
        )
        self.data_link_label.pack(pady=10)

        # Interpretation line
        tk.Label(
            self.root,
            text="INTERPRETATION: COMBAT TRIAGE THRESHOLDS",
            font=("Helvetica", 11, "italic"),
            fg="gray",
            bg="#121212"
        ).pack(pady=10)

    def create_metric(self, title, unit):
        frame = tk.Frame(self.root, bg="#1f1f1f", pady=10)
        frame.pack(fill="x", padx=20, pady=8)

        tk.Label(
            frame,
            text=title,
            font=("Helvetica", 16, "bold"),
            fg="white",
            bg="#1f1f1f"
        ).pack()

        value_label = tk.Label(
            frame,
            text=f"-- {unit}",
            font=("Helvetica", 26),
            fg="white",
            bg="#1f1f1f"
        )
        value_label.pack()

        flag_label = tk.Label(
            frame,
            text="STATUS: NORMAL",
            font=("Helvetica", 14, "bold"),
            fg="black",
            bg="lime",
            width=18
        )
        flag_label.pack(pady=5)

        return value_label, flag_label

    # SIMULATION
    def simulate_sensors(self):
        immobile_time = int(time.time() - self.last_motion_time)

        if immobile_time >= IMMOBILE_UNRESPONSIVE:
            hr = 0
            spo2 = random.randint(75, 89)
        else:
            hr = random.randint(45, 190)
            spo2 = random.randint(88, 99)

        sys = random.randint(80, 170)
        dia = random.randint(50, 100)

        motion = random.choice([True] * 7 + [False] * 3)
        if motion:
            self.last_motion_time = time.time()
            self.fall_detected = False
        else:
            self.fall_detected = True

        return hr, spo2, sys, dia

    def simulate_data_link(self):
        r = random.random()
        if r < 0.8:
            return "ACTIVE"
        elif r < 0.95:
            return "INTERMITTENT"
        else:
            return "LOST"

    # UPDATE LOOP
    def update_data(self):
        hr, spo2, sys, dia = self.simulate_sensors()
        immobile_time = int(time.time() - self.last_motion_time)

        self.hr_label.config(text=f"{hr} BPM")
        self.spo2_label.config(text=f"{spo2} %")
        self.bp_label.config(text=f"{sys}/{dia} mmHg")

        self.set_flag(self.hr_flag, self.hr_status(hr))
        self.set_flag(self.spo2_flag, self.spo2_status(spo2))
        self.set_flag(self.bp_flag, self.bp_status(sys))

        self.immobile_label.config(text=f"IMMOBILE TIME: {immobile_time} s")

        if self.fall_detected:
            self.fall_label.config(text="FALL STATUS: FALL DETECTED", fg="red")
        else:
            self.fall_label.config(text="FALL STATUS: NO FALL DETECTED", fg="lime")

        status, color = self.evaluate_health(hr, spo2, immobile_time)
        self.status_label.config(text=f"STATUS: {status}", fg=color)

        link = self.simulate_data_link()
        self.data_link_label.config(
            text=f"DATA LINK: {link}",
            fg="lime" if link == "ACTIVE" else "yellow" if link == "INTERMITTENT" else "red"
        )

        self.root.after(UPDATE_INTERVAL, self.update_data)

    # STATUS LOGIC (COMBAT)
    def set_flag(self, label, status):
        colors = {"NORMAL": "lime", "WARNING": "yellow", "CRITICAL": "red"}
        label.config(text=f"STATUS: {status}", bg=colors[status])

    def hr_status(self, hr):
        if hr < 50 or hr > 175:
            return "CRITICAL"
        elif hr < 60:
            return "WARNING"
        else:
            return "NORMAL"

    def spo2_status(self, spo2):
        if spo2 < 92:
            return "CRITICAL"
        elif spo2 < 95:
            return "WARNING"
        else:
            return "NORMAL"

    def bp_status(self, sys):
        if sys <= 100 or sys >= 160:
            return "CRITICAL"
        elif sys < 100 or sys >= 140:
            return "WARNING"
        else:
            return "NORMAL"

    def evaluate_health(self, hr, spo2, immobile):
        if immobile >= IMMOBILE_UNRESPONSIVE and (hr == 0 or spo2 < 90):
            return "UNRESPONSIVE", "red"
        elif (
            hr < 50 or hr > 175 or
            spo2 < 92 or
            immobile >= IMMOBILE_CRITICAL
        ):
            return "CRITICAL", "red"
        elif spo2 < 95 or hr < 60:
            return "MONITOR", "yellow"
        else:
            return "STABLE", "lime"

# RUN
if __name__ == "__main__":
    root = tk.Tk()
    app = TriageGUI(root)
    root.mainloop()