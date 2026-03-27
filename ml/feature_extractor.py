import numpy as np
import pandas as pd
import neurokit2 as nk
from scipy.stats import skew, kurtosis
from scipy.signal import welch

SAMPLING_RATE_IMU = 32  # PPG-DaLiA's chest IMU is 32 Hz
SAMPLING_RATE_ECG = 700 # Example rate (700) for ECG from PPG-DaLiA # For vitalDB use 500
SAMPLING_RATE_PPG = 64  # PPG-DaLiA's wrist PPG is 64 Hz # For vitalDB use 100

def process_imu(imu_window):
    """
    Extracts features from a 3-axis IMU data window.
    'imu_window' is a NumPy array of shape (window_size, 3)
    """
    features = {}
    
    # For each axis (x, y, z)
    for i, axis in enumerate(['x', 'y', 'z']):
        axis_data = imu_window[:, i]
        
        # Time-domain features
        features[f'acc_{axis}_mean'] = np.mean(axis_data)
        features[f'acc_{axis}_std'] = np.std(axis_data)
        features[f'acc_{axis}_var'] = np.var(axis_data)
        features[f'acc_{axis}_min'] = np.min(axis_data)
        features[f'acc_{axis}_max'] = np.max(axis_data)
        features[f'acc_{axis}_skew'] = skew(axis_data)
        features[f'acc_{axis}_kurt'] = kurtosis(axis_data)
        
    # Combined axis features
    acc_mag = np.sqrt(np.sum(imu_window**2, axis=1))
    features['acc_mag_mean'] = np.mean(acc_mag)
    features['acc_mag_std'] = np.std(acc_mag)

    return features

def extract_vitals_from_signals(ecg_signal, ppg_signal):
    """
    Uses NeuroKit2 to process raw ECG and PPG signals.
    'ecg_signal' and 'ppg_signal' are 1D NumPy arrays.
    """
    # Process ECG
    # Note: 'sampling_rate' Needs to match data! Change to match your data.
    try:
        ecg_signals, ecg_info = nk.ecg_process(ecg_signal, sampling_rate=SAMPLING_RATE_ECG)
        ecg_hr = ecg_signals['ECG_Rate'].mean()
        hrv_rmssd = ecg_signals['HRV_RMSSD'].mean()
        # EDR (ECG-Derived Respiration)
        edr = ecg_signals['RSP_Rate'].mean()
    except Exception as e:
        print(f"ECG processing failed: {e}")
        ecg_hr, hrv_rmssd, edr = np.nan, np.nan, np.nan

    # Process PPG
    try:
        ppg_signals, ppg_info = nk.ppg_process(ppg_signal, sampling_rate=SAMPLING_RATE_PPG)
        ppg_hr = ppg_signals['PPG_Rate'].mean()
        # Note: NeuroKit doesn't give SpO2 or Perfusion Index.
        # SpO2 requires TWO PPG wavelengths (Red and IR), which MAXREFDES117# provides.
        # PI is the AC/DC component of the PPG.
        # For now, just using PPG_Rate.
        # If needed, implement calculations to obtain SpO2 and PI.
    except Exception as e:
        print(f"PPG processing failed: {e}")
        ppg_hr = np.nan
    
    return {
        'ecg_hr': ecg_hr,
        'hrv_rmssd': hrv_rmssd,
        'breathing_rate_edr': edr,
        'ppg_hr': ppg_hr
        # 'spo2': ...
        # 'pi': ... 
    }