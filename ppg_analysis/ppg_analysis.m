% Analyze raw PPG daa and reference HR/SpO2 data
%% Load data
Tppg = readtable('data/ppg_raw_loc_a.csv');
Tref = readtable('data/ppg_ref_loc_a.csv');

% Convert timestamps into datetime objects
Tppg.timestamp = datetime(Tppg.timestamp, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS');
Tref.timestamp = datetime(Tref.timestamp, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS');

% Get list of windows from the PPG samples file
win_ids = unique(Tppg.window);

% Choose window to analyze
window = 13;  % 

% Initial SpO2 calibration constants
SPO2_A = 110;
SPO2_B = 25;

% Trim noisy start of each window
trim_sec = 0.13;

%% Get median reference HR / SpO2 for each window

num_windows = length(win_ids);

true_hr_all = nan(num_windows,1);
true_spo2_all = nan(num_windows,1);
num_ref_all = zeros(num_windows,1);

for k = 1:num_windows
    w_k = win_ids(k);

    idx_ref = Tref.window == w_k;
    Tw_ref = Tref(idx_ref,:);

    if height(Tw_ref) == 0
        continue;
    end

    % Use median of all user-entered readings in this window
    true_hr_all(k) = median(Tw_ref.true_hr, 'omitnan');
    true_spo2_all(k) = median(Tw_ref.true_spo2, 'omitnan');
    num_ref_all(k) = height(Tw_ref);
end

%% Compute HR, R, and SpO2 for each window

est_hr_all = nan(num_windows,1);
err_hr_all = nan(num_windows,1);
fs_all = nan(num_windows,1);

est_spo2_all = nan(num_windows,1);
err_spo2_all = nan(num_windows,1);
R_all = nan(num_windows,1);

for k = 1:num_windows
    w_k = win_ids(k);

    Tw_k = Tppg(Tppg.window == w_k,:); % PPG samples for this window

    % Skip if the window is too short
    if height(Tw_k) < 3
        continue;
    end

    % Need at least one reference value for comparison
    if isnan(true_hr_all(k)) || isnan(true_spo2_all(k))
        continue;
    end

    % Raw IR and red signals
    ir_raw_k = double(Tw_k.ir_raw);
    red_raw_k = double(Tw_k.red_raw);

    % Time axis for this window
    t_k = seconds(Tw_k.timestamp - Tw_k.timestamp(1));

    % Estimate sampling rate from timestamp spacing
    dt_k = seconds(diff(Tw_k.timestamp));
    dt_k = dt_k(dt_k > 0);

    if isempty(dt_k)
        continue;
    end

    fs_k = 1 / median(dt_k);
    fs_all(k) = fs_k;

    % Remove DC offset
    ir0_k = ir_raw_k - mean(ir_raw_k);
    red0_k = red_raw_k - mean(red_raw_k);

    % Skip windows too short for filtfilt
    if length(ir0_k) <= 12 || length(red0_k) <= 12
        fprintf('Skipping window %d: only %d samples\n', w_k, min(length(ir0_k), length(red0_k)));
        continue;
    end

    % Pulse band
    low_cut = 0.7;
    high_cut = min(3.5, 0.45 * fs_k);

    % Skip if fs is too low
    if fs_k <= 2 * low_cut || high_cut <= low_cut
        fprintf('Skipping window %d: fs = %.3f Hz is too low/invalid for bandpass\n', w_k, fs_k);
        continue;
    end

    % Bandpass filter
    [b_k, a_k] = butter(2, [low_cut high_cut] / (fs_k/2), 'bandpass');
    ir_k = filtfilt(b_k, a_k, ir0_k);
    red_k = filtfilt(b_k, a_k, red0_k);

    % Skip if filtered signal is flat
    if std(ir_k) == 0 || std(red_k) == 0
        continue;
    end

    % Normalize IR
    ir_norm_k = ir_k / std(ir_k);

    % Trim noisy start
    start_idx_trim_k = find(t_k >= trim_sec, 1, 'first');
    if isempty(start_idx_trim_k)
        continue;
    end

    ir_k_trim = ir_k(start_idx_trim_k:end);
    red_k_trim = red_k(start_idx_trim_k:end);
    ir_norm_k_trim = ir_norm_k(start_idx_trim_k:end);
    ir_raw_k_trim = ir_raw_k(start_idx_trim_k:end);
    red_raw_k_trim = red_raw_k(start_idx_trim_k:end);

    if length(ir_norm_k_trim) < 3 || length(red_k_trim) < 3
        continue;
    end

    % Peak detection
    min_peak_dist_k = min(round(fs_k * 0.4), length(ir_norm_k_trim) - 2);

    if min_peak_dist_k < 1
        continue;
    end

    [~, locs_k] = findpeaks(ir_norm_k_trim, 'MinPeakDistance', min_peak_dist_k);

    % HR estimate
    if length(locs_k) >= 2
        ibi_k = diff(locs_k) / fs_k;
        est_hr_all(k) = 60 / mean(ibi_k);
        err_hr_all(k) = est_hr_all(k) - true_hr_all(k);
    end

    % SpO2 ratio-of-ratios
    ir_dc_k = mean(ir_raw_k_trim);
    red_dc_k = mean(red_raw_k_trim);

    ir_ac_k = 0.5 * (max(ir_k_trim) - min(ir_k_trim));
    red_ac_k = 0.5 * (max(red_k_trim) - min(red_k_trim));

    if ir_dc_k > 0 && red_dc_k > 0 && ir_ac_k > 0 && red_ac_k > 0
        R_k = (red_ac_k / red_dc_k) / (ir_ac_k / ir_dc_k);
        R_all(k) = R_k;

        % Initial estimate using starting constants
        est_spo2_all(k) = SPO2_A - SPO2_B * R_k;
        est_spo2_all(k) = min(100, est_spo2_all(k));
        err_spo2_all(k) = est_spo2_all(k) - true_spo2_all(k);
    end
end

%% Fit SpO2 calibration line: true_spo2 = A - B*R

valid_fit_idx = ~isnan(R_all) & ~isnan(true_spo2_all);

R_fit = R_all(valid_fit_idx);
spo2_fit = true_spo2_all(valid_fit_idx);

if numel(R_fit) < 2
    error('Not enough valid windows to fit SpO2 calibration line.')
end

% spo2 = m*R + c
p = polyfit(R_fit, spo2_fit, 1);

m_fit = p(1);
c_fit = p(2);

% Convert to form: spo2 = A - B*R
SPO2_A_fit = c_fit;
SPO2_B_fit = -m_fit;

disp('Fitted SpO2 calibration:')
disp(['  SPO2_A = ', num2str(SPO2_A_fit)])
disp(['  SPO2_B = ', num2str(SPO2_B_fit)])
disp(['  Fitted line: SpO2 = ', num2str(SPO2_A_fit), ' - ', num2str(SPO2_B_fit), ' * R'])

%% Recompute SpO2 estimates using fitted calibration constants

est_spo2_fit_all = nan(num_windows,1);
err_spo2_fit_all = nan(num_windows,1);

for k = 1:num_windows
    if ~isnan(R_all(k)) && ~isnan(true_spo2_all(k))
        est_spo2_fit_all(k) = SPO2_A_fit - SPO2_B_fit * R_all(k);
        est_spo2_fit_all(k) = min(100, est_spo2_fit_all(k));
        err_spo2_fit_all(k) = est_spo2_fit_all(k) - true_spo2_all(k);
    end
end

%% Summary metrics

valid_hr_idx = ~isnan(est_hr_all) & ~isnan(true_hr_all);
mae_hr = mean(abs(err_hr_all(valid_hr_idx)));

valid_spo2_idx = ~isnan(est_spo2_fit_all) & ~isnan(true_spo2_all);
mae_spo2 = mean(abs(err_spo2_fit_all(valid_spo2_idx)));

results_table = table(win_ids, num_ref_all, fs_all, ...
    est_hr_all, true_hr_all, err_hr_all, ...
    R_all, est_spo2_fit_all, true_spo2_all, err_spo2_fit_all, ...
    'VariableNames', {'window','num_ref','fs', ...
    'estimated_hr','true_hr','error_hr', ...
    'R','estimated_spo2','true_spo2','error_spo2'});

disp(results_table)
disp(['Mean Absolute Error (HR) = ', num2str(mae_hr), ' bpm'])
disp(['Mean Absolute Error (SpO2) = ', num2str(mae_spo2), ' %'])

%% Plot: window vs HR
figure
plot(win_ids(valid_hr_idx), true_hr_all(valid_hr_idx), 'k-o', 'LineWidth', 1.5, 'MarkerSize', 5)
hold on
plot(win_ids(valid_hr_idx), est_hr_all(valid_hr_idx), 'r-s', 'LineWidth', 1.5, 'MarkerSize', 5)
xlabel('Window')
ylabel('Heart Rate (bpm)')
title(sprintf('Window vs HR (median reference) | MAE = %.2f bpm', mae_hr))
legend('True HR', 'Estimated HR', 'Location', 'best')
grid on

%% Plot: window vs SpO2 using fitted calibration
figure
plot(win_ids(valid_spo2_idx), true_spo2_all(valid_spo2_idx), 'k-o', 'LineWidth', 1.5, 'MarkerSize', 5)
hold on
plot(win_ids(valid_spo2_idx), est_spo2_fit_all(valid_spo2_idx), 'b-s', 'LineWidth', 1.5, 'MarkerSize', 5)
xlabel('Window')
ylabel('SpO2 (%)')
title(sprintf('Window vs SpO2 (fitted calibration) | MAE = %.2f %%', mae_spo2))
legend('True SpO2', 'Estimated SpO2', 'Location', 'best')
grid on

%% Plot SpO2 calibration fit
figure
scatter(R_fit, spo2_fit, 50, 'filled')
hold on
R_line = linspace(min(R_fit), max(R_fit), 200);
spo2_line = polyval(p, R_line);
plot(R_line, spo2_line, 'r-', 'LineWidth', 1.5)
xlabel('R = (red_{AC}/red_{DC}) / (ir_{AC}/ir_{DC})')
ylabel('True SpO2 (%)')
title('SpO2 Calibration Fit')
legend('Calibration windows', 'Fitted line', 'Location', 'best')
grid on

%% Inspect one selected window

w = win_ids(window);

% PPG data for this window
idx_ppg = Tppg.window == w;
Tw = Tppg(idx_ppg,:);

% Reference data for this window
idx_ref = Tref.window == w;
Tw_ref = Tref(idx_ref,:);

if height(Tw) < 3
    error('Selected window has too few PPG samples.')
end

if height(Tw_ref) == 0
    error('Selected window has no reference readings.')
end

true_hr_window = median(Tw_ref.true_hr, 'omitnan');
true_spo2_window = median(Tw_ref.true_spo2, 'omitnan');

% Time axis
t = seconds(Tw.timestamp - Tw.timestamp(1));

% Raw signals
ir_raw = double(Tw.ir_raw);
red_raw = double(Tw.red_raw);

% Estimate sampling rate
dt = seconds(diff(Tw.timestamp));
dt = dt(dt > 0);
fs = 1 / median(dt);

% Remove DC offset
ir0 = ir_raw - mean(ir_raw);
red0 = red_raw - mean(red_raw);

if length(ir0) <= 12 || length(red0) <= 12
    error('Selected window is too short for filtfilt.')
end

% Pulse band
low_cut = 0.7;
high_cut = min(3.5, 0.45 * fs);

if fs <= 2 * low_cut || high_cut <= low_cut
    error('Selected window has invalid or too-low sampling rate for this bandpass filter.')
end

% Filter
[b, a] = butter(2, [low_cut high_cut] / (fs/2), 'bandpass');
ir = filtfilt(b, a, ir0);
red = filtfilt(b, a, red0);

% Normalize for plotting
ir_raw_norm = (ir_raw - mean(ir_raw)) / std(ir_raw);
red_raw_norm = (red_raw - mean(red_raw)) / std(red_raw);

ir_norm = ir / std(ir);
red_norm = red / std(red);

% Trim noisy beginning
start_idx_trim = find(t >= trim_sec, 1, 'first');
if isempty(start_idx_trim)
    error('Trim time is longer than this selected window.')
end

t_trim = t(start_idx_trim:end);
ir_trim = ir(start_idx_trim:end);
red_trim = red(start_idx_trim:end);
ir_norm_trim = ir_norm(start_idx_trim:end);
ir_raw_trim = ir_raw(start_idx_trim:end);
red_raw_trim = red_raw(start_idx_trim:end);

% Detect peaks
min_peak_dist = min(round(fs * 0.4), length(ir_norm_trim) - 2);

if min_peak_dist < 1
    pks = [];
    locs = [];
else
    [pks, locs] = findpeaks(ir_norm_trim, 'MinPeakDistance', min_peak_dist);
end

% Estimate HR for this window
if length(locs) >= 2
    ibi = diff(locs) / fs;
    hr_est = 60 / mean(ibi);
    hr_err = hr_est - true_hr_window;

    disp(['Estimated HR = ', num2str(hr_est), ' bpm'])
    disp(['True HR      = ', num2str(true_hr_window), ' bpm'])
    disp(['Error        = ', num2str(hr_err), ' bpm'])
else
    hr_est = NaN;
    hr_err = NaN;
    disp('Estimated HR = not enough peaks detected')
    disp(['True HR      = ', num2str(true_hr_window), ' bpm'])
end

% Estimate SpO2 for this window using fitted constants
ir_dc = mean(ir_raw_trim);
red_dc = mean(red_raw_trim);

ir_ac = 0.5 * (max(ir_trim) - min(ir_trim));
red_ac = 0.5 * (max(red_trim) - min(red_trim));

if ir_dc > 0 && red_dc > 0 && ir_ac > 0 && red_ac > 0
    R = (red_ac / red_dc) / (ir_ac / ir_dc);
    spo2_est = SPO2_A_fit - SPO2_B_fit * R;
    spo2_est = min(100, spo2_est);
    spo2_err = spo2_est - true_spo2_window;

    % disp(['Window R value  = ', num2str(R)])
    disp(['Estimated SpO2 = ', num2str(spo2_est), ' %'])
    disp(['True SpO2      = ', num2str(true_spo2_window), ' %'])
    disp(['Error          = ', num2str(spo2_err), ' %'])
else
    R = NaN;
    spo2_est = NaN;
    spo2_err = NaN;
    disp('Estimated SpO2 = could not compute')
    disp(['True SpO2      = ', num2str(true_spo2_window), ' %'])
end

% Frequency axis for FFT
N = length(ir_trim);
f = (0:floor(N/2)) * fs / N;

%% Plot raw vs filtered signals for selected window
figure

subplot(2,1,1)
plot(t, ir_raw_norm, 'Color', [0.85 0.85 0.85])
hold on
plot(t, ir_norm, 'k', 'LineWidth', 1.0)
plot(t_trim(locs), pks, 'bo')
xline(trim_sec, '--b', 'Trim Start')
xlabel('Time (s)')
ylabel('Normalized Amplitude')
title(sprintf('IR Raw vs Filtered (Window %d)', w))
legend('Raw', 'Bandpass', 'Peaks', 'Trim Start')
grid on

subplot(2,1,2)
plot(t, red_raw_norm, 'Color', [0.85 0.85 0.85])
hold on
plot(t, red_norm, 'r', 'LineWidth', 1.0)
xline(trim_sec, '--b', 'Trim Start')
xlabel('Time (s)')
ylabel('Normalized Amplitude')
title('Red Raw vs Filtered')
legend('Raw', 'Bandpass', 'Trim Start')
grid on

%% FFT of trimmed filtered signals
Y_ir = fft(ir_trim);
Y_red = fft(red_trim);

P_ir = abs(Y_ir / N);
P_ir = P_ir(1:floor(N/2)+1);

P_red = abs(Y_red / N);
P_red = P_red(1:floor(N/2)+1);

figure
plot(f, P_ir, 'k', 'LineWidth', 1.5)
hold on
plot(f, P_red, 'r', 'LineWidth', 1.5)
xlim([0 5])
xlabel('Frequency (Hz)')
ylabel('Amplitude')
title(sprintf('PPG FFT Spectrum (Window %d)', w))
legend('IR', 'Red')
grid on

%% Plot reference readings inside this selected window
% Shows multiple entered HR / SpO2 values for the same window

t_ref = seconds(Tw_ref.timestamp - Tw.timestamp(1));

figure

subplot(2,1,1)
plot(t_ref, Tw_ref.true_hr, 'ko-', 'LineWidth', 1.2, 'MarkerSize', 6)
hold on
yline(true_hr_window, '--k', 'Median True HR')
if ~isnan(hr_est)
    yline(hr_est, '--r', 'Estimated HR')
end
xlabel('Time within window (s)')
ylabel('Heart Rate (bpm)')
title(sprintf('Reference HR Readings in Window %d', w))
legend('Entered HR', 'Median True HR', 'Estimated HR', 'Location', 'best')
grid on

subplot(2,1,2)
plot(t_ref, Tw_ref.true_spo2, 'ko-', 'LineWidth', 1.2, 'MarkerSize', 6)
hold on
yline(true_spo2_window, '--k', 'Median True SpO2')
if ~isnan(spo2_est)
    yline(spo2_est, '--b', 'Estimated SpO2')
end
xlabel('Time within window (s)')
ylabel('SpO2 (%)')
title(sprintf('Reference SpO2 Readings in Window %d', w))
legend('Entered SpO2', 'Median True SpO2', 'Estimated SpO2', 'Location', 'best')
grid on