This folder contains the IMU motion detection and analysis pipeline.

Workflow:
1. Flash imu_fsm.ino to stream IMU data and motion state outputs
2. Run imu_serial.py to save streamed IMU data to CSV during testing
3. Run imu_visualize.m to inspect a single recorded CSV file
4. Run imu_split_events.py to split long recordings into individual event windows for analysis (increase sample size)
5. Run imu_find_thresholds.m to compare statistics across multiple CSV files and tune detection thresholds and
   generate a classifier confusion matrix over the provided data
6. Run imu_check_accuracy.m to check the overall and per-event classification accuracy

Generally based on:
Tseng et al., "Wearable Fall Detection System with Real-Time Localization and Notification Capabilities," Sensors, 2025.
https://pmc.ncbi.nlm.nih.gov/articles/PMC12196599/

Extended to incorporate limping, walking, running, jumping, sitting/squat motion detection as well

Notes:
- Testing should be done over serial to achieve ~100 Hz data rate; Bluetooth is slower and not reliable for this stage.
- Perform each action for ~5–6 seconds so the FSM has enough time to move through the relevant states.
- Device orientation matters: keep the board horizontal (USB-C port facing left or right on the chest).
- Turning while walking/running is fine; the algorithm primarily relies on accelerometer-based features.
- Update the OUTPUT_FILE parameters in imu_serial.py before each test to keep recordings organized.