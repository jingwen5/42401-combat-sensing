% Analyze raw PPG data and reference HR/SpO2 data
%% Load data
Tppg = readtable('data/ppg_raw_loc_a.csv');
Tref = readtable('data/ppg_ref_loc_a.csv');

% Convert timestamps into datetime objects
Tppg.timestamp = datetime(Tppg.timestamp, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS');
Tref.timestamp = datetime(Tref.timestamp, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS');

% Get list of windows from the PPG samples file
win_ids = unique(Tppg.window);

% Choose window to analyze
window = 13;

% Initial SpO2 calibration constants
SPO2_A = 110;
SPO2_B = 25;

% Trim noisy start of each window
trim_sec = 0.13;

%% Poster Figure Settings
FONT       = 'Helvetica';
FONT_SIZE  = 22;
TITLE_SIZE = 24;
LEG_SIZE   = 20;
LINE_W     = 3.0;
AX_LINE_W  = 2.5;
MRK_SIZE   = 11;
FIG_W      = 1100;
FIG_H_1    = 520;

% Color palette
C_BLACK = [0.05 0.05 0.05];
C_RED   = [0.85 0.15 0.10];
C_BLUE  = [0.10 0.35 0.80];
C_GRAY  = [0.55 0.55 0.55];

applyPosterStyle = @(ax) set(ax, ...
    'FontName',      FONT, ...
    'FontSize',      FONT_SIZE, ...
    'LineWidth',     AX_LINE_W, ...
    'TickLength',    [0.012 0.012], ...
    'Box',           'on', ...
    'XColor',        C_BLACK, ...
    'YColor',        C_BLACK, ...
    'GridAlpha',     0.15, ...
    'GridLineStyle', ':');

%% Get median reference HR / SpO2 for each window

num_windows = length(win_ids);

true_hr_all   = nan(num_windows,1);
true_spo2_all = nan(num_windows,1);
num_ref_all   = zeros(num_windows,1);

for k = 1:num_windows
    w_k     = win_ids(k);
    idx_ref = Tref.window == w_k;
    Tw_ref  = Tref(idx_ref,:);

    if height(Tw_ref) == 0, continue; end

    true_hr_all(k)   = median(Tw_ref.true_hr,   'omitnan');
    true_spo2_all(k) = median(Tw_ref.true_spo2, 'omitnan');
    num_ref_all(k)   = height(Tw_ref);
end

%% Compute HR, R, and SpO2 for each window

est_hr_all   = nan(num_windows,1);
err_hr_all   = nan(num_windows,1);
fs_all       = nan(num_windows,1);
est_spo2_all = nan(num_windows,1);
err_spo2_all = nan(num_windows,1);
R_all        = nan(num_windows,1);

for k = 1:num_windows
    w_k  = win_ids(k);
    Tw_k = Tppg(Tppg.window == w_k,:);

    if height(Tw_k) < 3, continue; end
    if isnan(true_hr_all(k)) || isnan(true_spo2_all(k)), continue; end

    ir_raw_k  = double(Tw_k.ir_raw);
    red_raw_k = double(Tw_k.red_raw);
    t_k       = seconds(Tw_k.timestamp - Tw_k.timestamp(1));

    dt_k = seconds(diff(Tw_k.timestamp));
    dt_k = dt_k(dt_k > 0);
    if isempty(dt_k), continue; end

    fs_k      = 1 / median(dt_k);
    fs_all(k) = fs_k;

    ir0_k  = ir_raw_k - mean(ir_raw_k);
    red0_k = red_raw_k - mean(red_raw_k);

    if length(ir0_k) <= 12 || length(red0_k) <= 12
        fprintf('Skipping window %d: only %d samples\n', w_k, min(length(ir0_k),length(red0_k)));
        continue;
    end

    low_cut  = 0.7;
    high_cut = min(3.5, 0.45 * fs_k);

    if fs_k <= 2*low_cut || high_cut <= low_cut
        fprintf('Skipping window %d: fs = %.3f Hz too low\n', w_k, fs_k);
        continue;
    end

    [b_k, a_k] = butter(2, [low_cut high_cut] / (fs_k/2), 'bandpass');
    ir_k  = filtfilt(b_k, a_k, ir0_k);
    red_k = filtfilt(b_k, a_k, red0_k);

    if std(ir_k) == 0 || std(red_k) == 0, continue; end

    ir_norm_k        = ir_k / std(ir_k);
    start_idx_trim_k = find(t_k >= trim_sec, 1, 'first');
    if isempty(start_idx_trim_k), continue; end

    ir_k_trim      = ir_k(start_idx_trim_k:end);
    red_k_trim     = red_k(start_idx_trim_k:end);
    ir_norm_k_trim = ir_norm_k(start_idx_trim_k:end);
    ir_raw_k_trim  = ir_raw_k(start_idx_trim_k:end);
    red_raw_k_trim = red_raw_k(start_idx_trim_k:end);

    if length(ir_norm_k_trim) < 3 || length(red_k_trim) < 3, continue; end

    min_peak_dist_k = min(round(fs_k * 0.4), length(ir_norm_k_trim) - 2);
    if min_peak_dist_k < 1, continue; end

    [~, locs_k] = findpeaks(ir_norm_k_trim, 'MinPeakDistance', min_peak_dist_k);

    if length(locs_k) >= 2
        ibi_k         = diff(locs_k) / fs_k;
        est_hr_all(k) = 60 / mean(ibi_k);
        err_hr_all(k) = est_hr_all(k) - true_hr_all(k);
    end

    ir_dc_k  = mean(ir_raw_k_trim);
    red_dc_k = mean(red_raw_k_trim);
    ir_ac_k  = 0.5 * (max(ir_k_trim)  - min(ir_k_trim));
    red_ac_k = 0.5 * (max(red_k_trim) - min(red_k_trim));

    if ir_dc_k > 0 && red_dc_k > 0 && ir_ac_k > 0 && red_ac_k > 0
        R_k             = (red_ac_k / red_dc_k) / (ir_ac_k / ir_dc_k);
        R_all(k)        = R_k;
        est_spo2_all(k) = SPO2_A - SPO2_B * R_k;
        est_spo2_all(k) = min(100, est_spo2_all(k));
        err_spo2_all(k) = est_spo2_all(k) - true_spo2_all(k);
    end
end

%% Fit SpO2 calibration line: true_spo2 = A - B*R

valid_fit_idx = ~isnan(R_all) & ~isnan(true_spo2_all);
R_fit    = R_all(valid_fit_idx);
spo2_fit = true_spo2_all(valid_fit_idx);

if numel(R_fit) < 2
    error('Not enough valid windows to fit SpO2 calibration line.')
end

p          = polyfit(R_fit, spo2_fit, 1);
m_fit      = p(1);
c_fit      = p(2);
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

valid_hr_idx   = ~isnan(est_hr_all)       & ~isnan(true_hr_all);
valid_spo2_idx = ~isnan(est_spo2_fit_all) & ~isnan(true_spo2_all);
mae_hr   = mean(abs(err_hr_all(valid_hr_idx)));
mae_spo2 = mean(abs(err_spo2_fit_all(valid_spo2_idx)));

results_table = table(win_ids, num_ref_all, fs_all, ...
    est_hr_all, true_hr_all, err_hr_all, ...
    R_all, est_spo2_fit_all, true_spo2_all, err_spo2_fit_all, ...
    'VariableNames', {'window','num_ref','fs', ...
    'estimated_hr','true_hr','error_hr', ...
    'R','estimated_spo2','true_spo2','error_spo2'});

disp(results_table)
disp(['Mean Absolute Error (HR)   = ', num2str(mae_hr),   ' bpm'])
disp(['Mean Absolute Error (SpO2) = ', num2str(mae_spo2), ' %'])

%% FIGURE 1: Window vs Heart Rate
hf1 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax1 = gca;

plot(win_ids(valid_hr_idx), true_hr_all(valid_hr_idx), ...
    'o-', 'Color', C_BLACK, 'LineWidth', LINE_W, 'MarkerSize', MRK_SIZE, ...
    'MarkerFaceColor', C_BLACK)
hold on
plot(win_ids(valid_hr_idx), est_hr_all(valid_hr_idx), ...
    's-', 'Color', C_RED, 'LineWidth', LINE_W, 'MarkerSize', MRK_SIZE, ...
    'MarkerFaceColor', C_RED)
xlabel('Window',           'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('Heart Rate (bpm)', 'FontName', FONT, 'FontSize', FONT_SIZE)
% title('Heart Rate: Measured vs Estimated', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Measured HR', 'Estimated HR', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
text(0.02, 0.05, sprintf('MAE = %.1f bpm', mae_hr), ...
    'Units', 'normalized', 'FontName', FONT, 'FontSize', FONT_SIZE, ...
    'BackgroundColor', 'white', 'EdgeColor', C_BLACK, 'LineWidth', 1.5)
grid on
applyPosterStyle(ax1);

%% FIGURE 2: Window vs SpO2
hf2 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax2 = gca;

plot(win_ids(valid_spo2_idx), true_spo2_all(valid_spo2_idx), ...
    'o-', 'Color', C_BLACK, 'LineWidth', LINE_W, 'MarkerSize', MRK_SIZE, ...
    'MarkerFaceColor', C_BLACK)
hold on
plot(win_ids(valid_spo2_idx), est_spo2_fit_all(valid_spo2_idx), ...
    's-', 'Color', C_BLUE, 'LineWidth', LINE_W, 'MarkerSize', MRK_SIZE, ...
    'MarkerFaceColor', C_BLUE)
xlabel('Window',   'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('SpO2 (%)', 'FontName', FONT, 'FontSize', FONT_SIZE)
% title('SpO2: Measured vs Estimated', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Measured SpO2', 'Estimated SpO2', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
text(0.02, 0.05, sprintf('MAE = %.1f%%', mae_spo2), ...
    'Units', 'normalized', 'FontName', FONT, 'FontSize', FONT_SIZE, ...
    'BackgroundColor', 'white', 'EdgeColor', C_BLACK, 'LineWidth', 1.5)
grid on
applyPosterStyle(ax2);

%% FIGURE 3: SpO2 Calibration Fit
hf3 = figure('Position', [50 50 FIG_H_1*1.1 FIG_H_1]);
ax3 = gca;

scatter(R_fit, spo2_fit, 120, C_BLACK, 'filled', 'MarkerFaceAlpha', 0.8)
hold on
R_line    = linspace(min(R_fit), max(R_fit), 200);
spo2_line = polyval(p, R_line);
plot(R_line, spo2_line, '-', 'Color', C_RED, 'LineWidth', LINE_W)
xlabel('R  =  (AC_{red}/DC_{red}) / (AC_{IR}/DC_{IR})', ...
    'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('Measured SpO2 (%)', 'FontName', FONT, 'FontSize', FONT_SIZE)
% title('SpO2 Calibration Fit', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Calibration windows', 'Fitted line', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
text(0.05, 0.12, sprintf('SpO2 = %.1f - %.1f*R', SPO2_A_fit, SPO2_B_fit), ...
    'Units', 'normalized', 'FontName', FONT, 'FontSize', FONT_SIZE-2, 'Color', C_RED)
grid on
applyPosterStyle(ax3);

%% Single-window setup
w = win_ids(window);

idx_ppg = Tppg.window == w;
Tw      = Tppg(idx_ppg,:);
idx_ref = Tref.window == w;
Tw_ref  = Tref(idx_ref,:);

if height(Tw) < 3,      error('Selected window has too few PPG samples.'); end
if height(Tw_ref) == 0, error('Selected window has no reference readings.'); end

true_hr_window   = median(Tw_ref.true_hr,   'omitnan');
true_spo2_window = median(Tw_ref.true_spo2, 'omitnan');

t       = seconds(Tw.timestamp - Tw.timestamp(1));
ir_raw  = double(Tw.ir_raw);
red_raw = double(Tw.red_raw);

dt = seconds(diff(Tw.timestamp));
dt = dt(dt > 0);
fs = 1 / median(dt);

ir0  = ir_raw  - mean(ir_raw);
red0 = red_raw - mean(red_raw);

if length(ir0) <= 12 || length(red0) <= 12
    error('Selected window is too short for filtfilt.')
end

low_cut  = 0.7;
high_cut = min(3.5, 0.45 * fs);

if fs <= 2*low_cut || high_cut <= low_cut
    error('Selected window has invalid sampling rate for bandpass filter.')
end

[b, a] = butter(2, [low_cut high_cut] / (fs/2), 'bandpass');
ir     = filtfilt(b, a, ir0);
red    = filtfilt(b, a, red0);

ir_raw_norm  = (ir_raw  - mean(ir_raw))  / std(ir_raw);
red_raw_norm = (red_raw - mean(red_raw)) / std(red_raw);
ir_norm      = ir  / std(ir);
red_norm     = red / std(red);

start_idx_trim = find(t >= trim_sec, 1, 'first');
if isempty(start_idx_trim), error('Trim time exceeds window length.'); end

t_trim       = t(start_idx_trim:end);
ir_trim      = ir(start_idx_trim:end);
red_trim     = red(start_idx_trim:end);
ir_norm_trim = ir_norm(start_idx_trim:end);
ir_raw_trim  = ir_raw(start_idx_trim:end);
red_raw_trim = red_raw(start_idx_trim:end);

min_peak_dist = min(round(fs * 0.4), length(ir_norm_trim) - 2);
if min_peak_dist < 1
    pks = []; locs = [];
else
    [pks, locs] = findpeaks(ir_norm_trim, 'MinPeakDistance', min_peak_dist);
end

% HR estimate
if length(locs) >= 2
    ibi    = diff(locs) / fs;
    hr_est = 60 / mean(ibi);
    hr_err = hr_est - true_hr_window;
    disp(['Estimated HR = ', num2str(hr_est), ' bpm'])
    disp(['True HR      = ', num2str(true_hr_window), ' bpm'])
    disp(['Error        = ', num2str(hr_err), ' bpm'])
else
    hr_est = NaN; hr_err = NaN;
    disp('Estimated HR = not enough peaks detected')
    disp(['True HR      = ', num2str(true_hr_window), ' bpm'])
end

% SpO2 estimate
ir_dc  = mean(ir_raw_trim);
red_dc = mean(red_raw_trim);
ir_ac  = 0.5 * (max(ir_trim)  - min(ir_trim));
red_ac = 0.5 * (max(red_trim) - min(red_trim));

if ir_dc > 0 && red_dc > 0 && ir_ac > 0 && red_ac > 0
    R        = (red_ac / red_dc) / (ir_ac / ir_dc);
    spo2_est = SPO2_A_fit - SPO2_B_fit * R;
    spo2_est = min(100, spo2_est);
    spo2_err = spo2_est - true_spo2_window;
    disp(['Estimated SpO2 = ', num2str(spo2_est), ' %'])
    disp(['True SpO2      = ', num2str(true_spo2_window), ' %'])
    disp(['Error          = ', num2str(spo2_err), ' %'])
else
    R = NaN; spo2_est = NaN; spo2_err = NaN;
    disp('Estimated SpO2 = could not compute')
    disp(['True SpO2      = ', num2str(true_spo2_window), ' %'])
end

% FFT
N      = length(ir_trim);
f_axis = (0:floor(N/2)) * fs / N;
Y_ir   = fft(ir_trim);
Y_red  = fft(red_trim);
P_ir   = abs(Y_ir(1:floor(N/2)+1)  / N);
P_red  = abs(Y_red(1:floor(N/2)+1) / N);

t_ref = seconds(Tw_ref.timestamp - Tw.timestamp(1));

%% FIGURE 4: IR — Raw vs Filtered
hf4 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax4 = gca;

plot(t, ir_raw_norm, '-', 'Color', C_GRAY, 'LineWidth', 2.0)
hold on
plot(t, ir_norm, '-', 'Color', C_BLACK, 'LineWidth', LINE_W)
plot(t_trim(locs), pks, 'o', 'Color', C_BLUE, ...
    'MarkerSize', MRK_SIZE+2, 'LineWidth', 2.5, 'MarkerFaceColor', 'none')
xline(trim_sec, '--', 'Color', C_BLUE, 'LineWidth', 2.0, ...
    'Label', 'Trim', 'FontSize', FONT_SIZE-2, 'FontName', FONT)
xlabel('Time (s)',             'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('Normalized Amplitude', 'FontName', FONT, 'FontSize', FONT_SIZE)
% title('IR Signal: Raw vs Filtered', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Unfiltered', 'Bandpass Filtered', 'Detected Peaks', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
grid on
applyPosterStyle(ax4);

%% FIGURE 5: Red — Raw vs Filtered
hf5 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax5 = gca;

plot(t, red_raw_norm, '-', 'Color', C_GRAY, 'LineWidth', 2.0)
hold on
plot(t, red_norm, '-', 'Color', C_RED, 'LineWidth', LINE_W)
xline(trim_sec, '--', 'Color', C_BLUE, 'LineWidth', 2.0, ...
    'Label', 'Trim', 'FontSize', FONT_SIZE-2, 'FontName', FONT)
xlabel('Time (s)',             'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('Normalized Amplitude', 'FontName', FONT, 'FontSize', FONT_SIZE)
% title('Red Signal: Raw vs Filtered', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Unfiltered', 'Bandpass Filtered', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
grid on
applyPosterStyle(ax5);

%% FIGURE 6: FFT Spectrum
hf6 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax6 = gca;

plot(f_axis, P_ir,  '-', 'Color', C_BLACK, 'LineWidth', LINE_W)
hold on
plot(f_axis, P_red, '-', 'Color', C_RED,   'LineWidth', LINE_W)
xlim([0 5])
xlabel('Frequency (Hz)', 'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('Amplitude',      'FontName', FONT, 'FontSize', FONT_SIZE)
% title('PPG Frequency Spectrum', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('IR', 'Red', 'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
grid on
applyPosterStyle(ax6);

%% FIGURE 7: Reference HR readings
hf7 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax7 = gca;

plot(t_ref, Tw_ref.true_hr, 'o-', 'Color', C_BLACK, ...
    'LineWidth', LINE_W, 'MarkerSize', MRK_SIZE, 'MarkerFaceColor', C_BLACK)
hold on
yline(true_hr_window, '--', 'Color', C_BLACK, 'LineWidth', 2.5, ...
    'Label', 'Measured (median)', 'FontSize', FONT_SIZE-2, 'FontName', FONT)
if ~isnan(hr_est)
    yline(hr_est, '--', 'Color', C_RED, 'LineWidth', 2.5, ...
        'Label', 'Estimated', 'FontSize', FONT_SIZE-2, 'FontName', FONT)
end
xlabel('Time within Window (s)', 'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('Heart Rate (bpm)',        'FontName', FONT, 'FontSize', FONT_SIZE)
% title('Heart Rate: Reference Readings', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Entered HR', 'Measured (median)', 'Estimated', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
grid on
applyPosterStyle(ax7);

%% FIGURE 8: Reference SpO2 readings
hf8 = figure('Position', [50 50 FIG_W FIG_H_1]);
ax8 = gca;

plot(t_ref, Tw_ref.true_spo2, 'o-', 'Color', C_BLACK, ...
    'LineWidth', LINE_W, 'MarkerSize', MRK_SIZE, 'MarkerFaceColor', C_BLACK)
hold on
yline(true_spo2_window, '--', 'Color', C_BLACK, 'LineWidth', 2.5, ...
    'Label', 'Measured (median)', 'FontSize', FONT_SIZE-2, 'FontName', FONT)
if ~isnan(spo2_est)
    yline(spo2_est, '--', 'Color', C_BLUE, 'LineWidth', 2.5, ...
        'Label', 'Estimated', 'FontSize', FONT_SIZE-2, 'FontName', FONT)
end
xlabel('Time within Window (s)', 'FontName', FONT, 'FontSize', FONT_SIZE)
ylabel('SpO2 (%)',                'FontName', FONT, 'FontSize', FONT_SIZE)
% title('SpO2: Reference Readings', 'FontName', FONT, 'FontSize', TITLE_SIZE)
legend('Entered SpO2', 'Measured (median)', 'Estimated', ...
    'Location', 'best', 'FontName', FONT, 'FontSize', LEG_SIZE, 'Box', 'off')
grid on
applyPosterStyle(ax8);

%% Export all figures as high-res PDFs
% Uncomment to save:
% exportgraphics(hf1, 'poster_hr_vs_window.pdf',    'Resolution', 300);
% exportgraphics(hf2, 'poster_spo2_vs_window.pdf',  'Resolution', 300);
% exportgraphics(hf3, 'poster_calibration_fit.pdf', 'Resolution', 300);
% exportgraphics(hf4, 'poster_ir_filtered.pdf',     'Resolution', 300);
% exportgraphics(hf5, 'poster_red_filtered.pdf',    'Resolution', 300);
% exportgraphics(hf6, 'poster_fft_spectrum.pdf',    'Resolution', 300);
% exportgraphics(hf7, 'poster_ref_hr_window.pdf',   'Resolution', 300);
% exportgraphics(hf8, 'poster_ref_spo2_window.pdf', 'Resolution', 300);