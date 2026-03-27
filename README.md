# 42401-combat-sensing

Wearable PPG + IMU system for heart rate, SpO2, and fall detection.

## Overview

This repo is organized into separate pipelines for different parts of the project.  
Each folder is mostly standalone and contains everything needed to run that part:
- MCU code (`.ino`)
- data collection scripts (Python)
- analysis scripts (MATLAB)
- local data and figures

You can work within a single folder without needing the rest of the repo, except for shared utilities used by the PPG pipelines.

---

## Setup (Python)

Create a virtual environment and install dependencies:

```bash
python -m venv venv
source venv/bin/activate        # macOS/Linux
venv\Scripts\activate           # Windows

pip install -r requirements.txt
```

---

## Folder Structure

### `ppg_analysis/`
Raw PPG data collection and calibration.
- Collect raw IR/Red signals over serial
- Record reference HR/SpO2
- Compute HR, SpO2, and calibration constants

### `ppg_eval/`
Evaluation of processed HR and SpO2 over BLE.
- Stream estimated HR/SpO2 from the device
- Compare estimates against reference readings

### `imu_analysis/`
IMU-based motion detection and fall detection.
- Collect accelerometer/gyro data
- Run FSM-based motion classification
- Tune thresholds and analyze events

### `gui/`
Visualization and demo interface.
- Displays vitals, motion status, and system state
- Used for testing and presentation

### `ml/`
ML models.
- Extract features from IMU / ECG / PPG data
- Train activity and triage models

### `utils/`
Shared helper functions used by the PPG pipelines.
- Includes parsing and utility code used by Python scripts

---

## General Workflow

Each pipeline follows a similar pattern:

1. Flash the `.ino` file to the device  
2. Run the Python script to collect or receive data  
3. Run the MATLAB script to analyze or evaluate results  

Refer to each folder’s `README.md` for exact steps.

---
