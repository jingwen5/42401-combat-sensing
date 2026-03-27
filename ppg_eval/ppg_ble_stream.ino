// ppg_ble_stream.ino
#include <Wire.h>
#include <MAX30105.h>
#include <Arduino.h>
#include <bluefruit.h>
#include <math.h>
#include <string.h>

BLEUart bleuart;
MAX30105 sensor;

// Start time for reference
uint32_t t0 = 0;

// Fixed sampling settings
#define FS_HZ 100.0f
#define WINDOW_SEC 5.0f
#define N_SAMPLES 500
#define TRIM_SEC 0.13f

// Fitted SpO2 calibration from MATLAB
#define SPO2_A 99.6061f
#define SPO2_B 4.7242f

// Minimum signal thresholds for valid contact
#define MIN_IR_DC 20000.0f
#define MIN_IR_AC 100.0f

// Raw PPG sample buffers
uint32_t ir_raw_buf[N_SAMPLES];
uint32_t red_raw_buf[N_SAMPLES];

// Working buffers for filtering and processing
float ir0[N_SAMPLES];
float red0[N_SAMPLES];
float ir_filt[N_SAMPLES];
float red_filt[N_SAMPLES];
float ir_norm[N_SAMPLES];
float scratch1[N_SAMPLES];
float scratch2[N_SAMPLES];

// Peak index buffer
int peak_locs[N_SAMPLES];

// Sample and window counters
int sample_idx = 0;
uint32_t window_counter = 0;

float mean_float(const float *x, int n) {
  float s = 0.0f;
  for (int i = 0; i < n; i++) {
    s += x[i];
  }
  return s / (float)n;
}

float mean_u32(const uint32_t *x, int n) {
  float s = 0.0f;
  for (int i = 0; i < n; i++) {
    s += (float)x[i];
  }
  return s / (float)n;
}

float std_float(const float *x, int n) {
  float m = mean_float(x, n);
  float s = 0.0f;
  for (int i = 0; i < n; i++) {
    float d = x[i] - m;
    s += d * d;
  }
  return sqrtf(s / (float)(n - 1));
}

float max_float(const float *x, int n) {
  float m = x[0];
  for (int i = 1; i < n; i++) {
    if (x[i] > m) {
      m = x[i];
    }
  }
  return m;
}

float min_float(const float *x, int n) {
  float m = x[0];
  for (int i = 1; i < n; i++) {
    if (x[i] < m) {
      m = x[i];
    }
  }
  return m;
}

// Reverse array for forward-backward filtering
void reverse_in_place(float *x, int n) {
  for (int i = 0; i < n / 2; i++) {
    float t = x[i];
    x[i] = x[n - 1 - i];
    x[n - 1 - i] = t;
  }
}

// One biquad filter section
void filter_biquad(const float *x, float *y, int n,
                   float b0, float b1, float b2,
                   float a1, float a2) {
  float z1 = 0.0f;
  float z2 = 0.0f;

  for (int i = 0; i < n; i++) {
    float out = b0 * x[i] + z1;
    z1 = b1 * x[i] - a1 * out + z2;
    z2 = b2 * x[i] - a2 * out;
    y[i] = out;
  }
}

// Approximate MATLAB filtfilt using forward and reverse passes
void bandpass_filtfilt(const float *x, float *y, int n) {
  filter_biquad(x, scratch1, n, 0.00686787f, 0.01373573f, 0.00686787f, -1.78602350f, 0.82036394f);
  filter_biquad(scratch1, scratch2, n, 1.00000000f, -2.00000000f, 1.00000000f, -1.94806585f, 0.95047992f);

  memcpy(scratch1, scratch2, n * sizeof(float));
  reverse_in_place(scratch1, n);

  filter_biquad(scratch1, scratch2, n, 0.00686787f, 0.01373573f, 0.00686787f, -1.78602350f, 0.82036394f);
  filter_biquad(scratch2, scratch1, n, 1.00000000f, -2.00000000f, 1.00000000f, -1.94806585f, 0.95047992f);

  reverse_in_place(scratch1, n);
  memcpy(y, scratch1, n * sizeof(float));
}

// Peak detector with minimum spacing between peaks
int find_peaks(const float *x, int n, int min_peak_dist, int *locs) {
  int count = 0;

  for (int i = 1; i < n - 1; i++) {
    if (x[i] > x[i - 1] && x[i] >= x[i + 1]) {
      if (count == 0) {
        locs[count++] = i;
      } else {
        int prev = locs[count - 1];
        if ((i - prev) >= min_peak_dist) {
          locs[count++] = i;
        } else if (x[i] > x[prev]) {
          locs[count - 1] = i;
        }
      }
    }
  }

  return count;
}

// Send one result packet: timestamp, HR, and SpO2
void send_result(float hr, float spo2) {
  if (!Bluefruit.connected()) {
    return;
  }

  uint32_t ts = (uint32_t)(window_counter * WINDOW_SEC * 1000.0f);

  int16_t hr_i = isnan(hr) ? -1 : (int16_t)lroundf(hr * 100.0f);
  int16_t spo2_i = isnan(spo2) ? -1 : (int16_t)lroundf(spo2 * 100.0f);

  uint8_t pkt[9];
  pkt[0] = 'R';
  memcpy(&pkt[1], &ts, 4);
  memcpy(&pkt[5], &hr_i, 2);
  memcpy(&pkt[7], &spo2_i, 2);

  bleuart.write(pkt, sizeof(pkt));
}

// Process one full PPG window
void process_window() {
  // Convert raw samples to float and keep only valid 18-bit PPG data
  for (int i = 0; i < N_SAMPLES; i++) {
    ir_raw_buf[i] &= 0x3FFFF;
    red_raw_buf[i] &= 0x3FFFF;
    ir0[i] = (float)ir_raw_buf[i];
    red0[i] = (float)red_raw_buf[i];
  }

  // Save raw IR level to help detect whether finger/contact is present
  float ir_dc_full = mean_float(ir0, N_SAMPLES);

  // Remove DC offset
  float ir_mean = ir_dc_full;
  float red_mean = mean_float(red0, N_SAMPLES);

  for (int i = 0; i < N_SAMPLES; i++) {
    ir0[i] -= ir_mean;
    red0[i] -= red_mean;
  }

  // Bandpass filter both channels
  bandpass_filtfilt(ir0, ir_filt, N_SAMPLES);
  bandpass_filtfilt(red0, red_filt, N_SAMPLES);

  // Skip bad windows if filtered signal is flat
  float ir_std = std_float(ir_filt, N_SAMPLES);
  float red_std = std_float(red_filt, N_SAMPLES);

  if (ir_std == 0.0f || red_std == 0.0f) {
    send_result(NAN, NAN);
    return;
  }

  // Ignore noisy beginning of window
  int start_idx_trim = 0;
  while (start_idx_trim < N_SAMPLES && ((float)start_idx_trim / FS_HZ) < TRIM_SEC) {
    start_idx_trim++;
  }

  int Nt = N_SAMPLES - start_idx_trim;
  if (Nt < 3) {
    send_result(NAN, NAN);
    return;
  }

  // Check whether the PPG signal is strong enough to trust
  float ir_dc = mean_u32(&ir_raw_buf[start_idx_trim], Nt);
  float ir_ac = 0.5f * (max_float(&ir_filt[start_idx_trim], Nt) - min_float(&ir_filt[start_idx_trim], Nt));

  if (ir_dc < MIN_IR_DC || ir_ac < MIN_IR_AC || ir_dc_full < MIN_IR_DC) {
    send_result(NAN, NAN);
    return;
  }

  // Normalize filtered IR for peak detection
  for (int i = 0; i < N_SAMPLES; i++) {
    ir_norm[i] = ir_filt[i] / ir_std;
  }

  // Find peaks with same spacing idea as MATLAB
  int min_peak_dist = (int)roundf(FS_HZ * 0.4f);
  if (min_peak_dist > Nt - 2) {
    min_peak_dist = Nt - 2;
  }
  if (min_peak_dist < 1) {
    send_result(NAN, NAN);
    return;
  }

  int n_peaks = find_peaks(&ir_norm[start_idx_trim], Nt, min_peak_dist, peak_locs);

  // Estimate HR from average beat-to-beat interval
  float hr_est = NAN;
  if (n_peaks >= 2) {
    float ibi_sum = 0.0f;
    for (int i = 1; i < n_peaks; i++) {
      ibi_sum += (float)(peak_locs[i] - peak_locs[i - 1]) / FS_HZ;
    }

    float mean_ibi = ibi_sum / (float)(n_peaks - 1);
    if (mean_ibi > 0.0f) {
      hr_est = 60.0f / mean_ibi;
    }
  }

  // Compute ratio-of-ratios for SpO2
  float red_dc = mean_u32(&red_raw_buf[start_idx_trim], Nt);
  float red_ac = 0.5f * (max_float(&red_filt[start_idx_trim], Nt) - min_float(&red_filt[start_idx_trim], Nt));

  float spo2_est = NAN;
  if (ir_dc > 0.0f && red_dc > 0.0f && ir_ac > 0.0f && red_ac > 0.0f) {
    float R = (red_ac / red_dc) / (ir_ac / ir_dc);
    spo2_est = SPO2_A - SPO2_B * R;

    if (spo2_est > 100.0f) {
      spo2_est = 100.0f;
    }
  }

  send_result(hr_est, spo2_est);
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  t0 = micros();

  Bluefruit.begin();
  Bluefruit.setName("XIAO-SENSE");
  bleuart.begin();
  Bluefruit.Advertising.addService(bleuart);
  Bluefruit.Advertising.addName();
  Bluefruit.Advertising.start(0);

  if (!sensor.begin(Wire, 400000)) {
    Serial.println("MAX30102 not found");
    while (1) {}
  }

  sensor.setup(
    60,
    4,
    2,
    100,
    411,
    4096
  );

  Serial.println("PPG HR/SpO2 ready.");
}

void loop() {
  int n = sensor.check();

  if (n == 0) {
    return;
  }

  while (n--) {
    ir_raw_buf[sample_idx] = sensor.getFIFOIR();
    red_raw_buf[sample_idx] = sensor.getFIFORed();
    sample_idx++;

    // Once one full window is collected, process and transmit result
    if (sample_idx >= N_SAMPLES) {
      process_window();
      sample_idx = 0;
      window_counter++;
    }
  }
}