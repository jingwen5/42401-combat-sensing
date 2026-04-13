% Configs

csv_file = 'integrated_XX.csv';

% Activity labels grouped into bins for MAE breakdown
STILL_LABELS = {'PPG_WARMUP', 'BASELINE_STILL', 'RECOVERY_STILL'};
MOVE_LABELS  = {'WALK_SLOW', 'WALK_FAST', 'RUN', ...
                'JUMP_SINGLE', 'JUMP_REPEATED'};
FALL_LABELS  = {'FALL_FORWARD', 'FALL_BACKWARD', 'FALL_SIDE'};
SIT_LABELS   = {'SIT_QUICK'};

% Mapping from activity_label to acceptable IMU states
% Multiple acceptable states per label because the classifier may
% transiently report related states (e.g., IDLE_FALL during pauses)
LABEL_TO_VALID_IMU = containers.Map();
LABEL_TO_VALID_IMU('PPG_WARMUP')     = {'IDLE_FALL', 'STATIONARY_POST_FALL'};
LABEL_TO_VALID_IMU('BASELINE_STILL') = {'IDLE_FALL', 'STATIONARY_POST_FALL'};
LABEL_TO_VALID_IMU('RECOVERY_STILL') = {'IDLE_FALL', 'STATIONARY_POST_FALL', 'SITTING'};
LABEL_TO_VALID_IMU('WALK_SLOW')      = {'WALKING', 'LIMPING'};
LABEL_TO_VALID_IMU('WALK_FAST')      = {'WALKING', 'LIMPING'};
LABEL_TO_VALID_IMU('RUN')            = {'RUNNING'};
LABEL_TO_VALID_IMU('JUMP_SINGLE')    = {'JUMPING', 'IDLE_FALL'};
LABEL_TO_VALID_IMU('JUMP_REPEATED')  = {'JUMPING'};
LABEL_TO_VALID_IMU('FALL_FORWARD')   = {'DETECTED_FALL', 'STATIONARY_POST_FALL'};
LABEL_TO_VALID_IMU('FALL_BACKWARD')  = {'DETECTED_FALL', 'STATIONARY_POST_FALL'};
LABEL_TO_VALID_IMU('FALL_SIDE')      = {'DETECTED_FALL', 'STATIONARY_POST_FALL'};
LABEL_TO_VALID_IMU('SIT_QUICK')      = {'SITTING', 'SQUATTING'};

% Figure colors
C_BLUE   = [0.20 0.40 0.75];
C_ORANGE = [0.90 0.45 0.15];
C_GREEN  = [0.20 0.65 0.35];
C_RED    = [0.85 0.25 0.25];
C_GRAY   = [0.55 0.55 0.55];

%% LOAD DATA

T = readtable(csv_file, 'Delimiter', ',', 'TextType', 'string');

% Standardise column types — readtable may import some as string
num_cols = {'ble_hr', 'ble_spo2', 'ref_hr', 'ref_spo2', ...
            'imu_event_val', 'imu_impact', 'ble_rr', ...
            'ble_sbp', 'ble_dbp', 'ble_vbat'};
for i = 1:numel(num_cols)
    col = num_cols{i};
    if ismember(col, T.Properties.VariableNames)
        if isstring(T.(col)) || iscellstr(T.(col))
            T.(col) = str2double(T.(col));
        end
    end
end

% Convert time to relative seconds from start
T.time = T.time - T.time(1);

fprintf('Loaded %d rows from %s\n', height(T), csv_file);

%%  1. HR & SpO2 MAE

% Average BLE and reference readings within each activity step,
% then compute error per step

labels_all = unique(T.activity_label, 'stable');

hr_errors  = [];
spo2_errors = [];
hr_bin     = {};   % activity bin label for each error entry
spo2_bin   = {};

for k = 1:numel(labels_all)
    lbl = labels_all(k);
    mask = T.activity_label == lbl;

    % Mean BLE readings for this step (ignore NaN / empty)
    ble_hr_vals   = T.ble_hr(mask);
    ble_spo2_vals = T.ble_spo2(mask);
    ref_hr_vals   = T.ref_hr(mask);
    ref_spo2_vals = T.ref_spo2(mask);

    mean_ble_hr   = mean(ble_hr_vals(~isnan(ble_hr_vals) & ble_hr_vals > 0), 'omitnan');
    mean_ble_spo2 = mean(ble_spo2_vals(~isnan(ble_spo2_vals) & ble_spo2_vals > 0), 'omitnan');
    mean_ref_hr   = mean(ref_hr_vals(~isnan(ref_hr_vals) & ref_hr_vals > 0), 'omitnan');
    mean_ref_spo2 = mean(ref_spo2_vals(~isnan(ref_spo2_vals) & ref_spo2_vals > 0), 'omitnan');

    % Determine bin
    lbl_char = char(lbl);
    if ismember(lbl_char, STILL_LABELS)
        bin_name = 'Still';
    elseif ismember(lbl_char, MOVE_LABELS)
        bin_name = 'Moving';
    elseif ismember(lbl_char, FALL_LABELS)
        bin_name = 'Fall';
    elseif ismember(lbl_char, SIT_LABELS)
        bin_name = 'Sit';
    else
        bin_name = 'Other';
    end

    if ~isnan(mean_ble_hr) && ~isnan(mean_ref_hr)
        hr_errors(end+1)  = mean_ble_hr - mean_ref_hr; %#ok<SAGROW>
        hr_bin{end+1}     = bin_name; %#ok<SAGROW>
    end
    if ~isnan(mean_ble_spo2) && ~isnan(mean_ref_spo2)
        spo2_errors(end+1) = mean_ble_spo2 - mean_ref_spo2; %#ok<SAGROW>
        spo2_bin{end+1}    = bin_name; %#ok<SAGROW>
    end
end

% Overall MAE
mae_hr_overall   = mean(abs(hr_errors));
mae_spo2_overall = mean(abs(spo2_errors));

fprintf('\n--- PPG Accuracy ---\n');
fprintf('HR   MAE (overall): %.2f bpm   (n=%d steps)\n', mae_hr_overall, numel(hr_errors));
fprintf('SpO2 MAE (overall): %.2f %%     (n=%d steps)\n', mae_spo2_overall, numel(spo2_errors));

% Per-bin MAE
bins = {'Still', 'Moving', 'Fall', 'Sit'};
fprintf('\nPer-activity-bin MAE:\n');
fprintf('%-10s  HR MAE (bpm)  SpO2 MAE (%%)\n', 'Bin');
fprintf('%-10s  -----------  ------------\n', '---');

hr_mae_per_bin   = nan(1, numel(bins));
spo2_mae_per_bin = nan(1, numel(bins));

for b = 1:numel(bins)
    hr_mask   = strcmp(hr_bin, bins{b});
    spo2_mask = strcmp(spo2_bin, bins{b});

    if any(hr_mask)
        hr_mae_per_bin(b) = mean(abs(hr_errors(hr_mask)));
    end
    if any(spo2_mask)
        spo2_mae_per_bin(b) = mean(abs(spo2_errors(spo2_mask)));
    end

    fprintf('%-10s  %11.2f  %12.2f\n', bins{b}, hr_mae_per_bin(b), spo2_mae_per_bin(b));
end

%%  2. IMU CLASSIFICATION ACCURACY

% Only look at rows that have an imu_state value
imu_rows = T(T.imu_state ~= "" & ~ismissing(T.imu_state), :);

n_correct = 0;
n_total   = 0;

% Per-label breakdown
imu_labels = unique(imu_rows.activity_label, 'stable');
imu_acc_table = table('Size', [numel(imu_labels), 3], ...
    'VariableTypes', {'string', 'double', 'double'}, ...
    'VariableNames', {'Activity', 'Correct', 'Total'});

for k = 1:numel(imu_labels)
    lbl = imu_labels(k);
    lbl_char = char(lbl);

    mask = imu_rows.activity_label == lbl;
    states_reported = imu_rows.imu_state(mask);

    if ~LABEL_TO_VALID_IMU.isKey(lbl_char)
        continue;  % skip labels we didn't define mappings for
    end

    valid = LABEL_TO_VALID_IMU(lbl_char);
    correct_k = sum(ismember(states_reported, valid));
    total_k   = numel(states_reported);

    n_correct = n_correct + correct_k;
    n_total   = n_total + total_k;

    imu_acc_table.Activity(k) = lbl;
    imu_acc_table.Correct(k)  = correct_k;
    imu_acc_table.Total(k)    = total_k;
end

imu_accuracy = n_correct / max(n_total, 1) * 100;

fprintf('\n--- IMU Classification ---\n');
fprintf('Overall accuracy: %.1f%%  (%d / %d packets)\n', imu_accuracy, n_correct, n_total);
fprintf('\nPer-activity breakdown:\n');
for k = 1:height(imu_acc_table)
    if imu_acc_table.Total(k) > 0
        acc = imu_acc_table.Correct(k) / imu_acc_table.Total(k) * 100;
        fprintf('  %-20s  %3d / %3d  (%.0f%%)\n', ...
            imu_acc_table.Activity(k), ...
            imu_acc_table.Correct(k), ...
            imu_acc_table.Total(k), acc);
    end
end

%%  3. CONFUSION-STYLE TABLE: what did IMU report during each activity?

% Build a table of counts: rows = activity labels, cols = reported IMU states
all_imu_states = unique(imu_rows.imu_state, 'stable');
confusion_counts = zeros(numel(imu_labels), numel(all_imu_states));

for k = 1:numel(imu_labels)
    mask = imu_rows.activity_label == imu_labels(k);
    states_k = imu_rows.imu_state(mask);
    for s = 1:numel(all_imu_states)
        confusion_counts(k, s) = sum(states_k == all_imu_states(s));
    end
end

fprintf('\nIMU state distribution per activity:\n');
fprintf('%-20s', 'Activity');
for s = 1:numel(all_imu_states)
    fprintf('  %12s', all_imu_states(s));
end
fprintf('\n');
for k = 1:numel(imu_labels)
    fprintf('%-20s', imu_labels(k));
    for s = 1:numel(all_imu_states)
        fprintf('  %12d', confusion_counts(k, s));
    end
    fprintf('\n');
end

%% FIGURE 1: HR and SpO2 MAE per activity bin (grouped bar)

fig1 = figure('Position', [100 100 600 380], 'Color', 'w');

% Only plot bins that have data
valid_bins = find(~isnan(hr_mae_per_bin) | ~isnan(spo2_mae_per_bin));
bar_data = [hr_mae_per_bin(valid_bins); spo2_mae_per_bin(valid_bins)]';
bar_labels = bins(valid_bins);

b = bar(bar_data, 0.75);
b(1).FaceColor = C_BLUE;
b(2).FaceColor = C_ORANGE;
b(1).EdgeColor = 'none';
b(2).EdgeColor = 'none';

set(gca, 'XTickLabel', bar_labels);
ylabel('Mean Absolute Error');
title('PPG Accuracy by Activity Type', 'FontWeight', 'bold');
legend({'HR (bpm)', 'SpO\x2082 (%)'}, 'Location', 'northwest', 'Box', 'off');
style_ax(gca);

% Add value labels on bars
for i = 1:numel(b)
    xdata = b(i).XEndPoints;
    ydata = b(i).YEndPoints;
    for j = 1:numel(xdata)
        if ~isnan(ydata(j)) && ydata(j) > 0
            text(xdata(j), ydata(j) + 0.3, sprintf('%.1f', ydata(j)), ...
                'HorizontalAlignment', 'center', 'FontSize', 9, ...
                'FontName', fig_font, 'Color', [.3 .3 .3]);
        end
    end
end

exportgraphics(fig1, 'fig_ppg_mae_by_bin.png', 'Resolution', 300);
fprintf('\nSaved fig_ppg_mae_by_bin.png\n');

%% FIGURE 2: HR time series (BLE vs reference)

fig2 = figure('Position', [100 100 800 350], 'Color', 'w');

% Plot BLE HR
ble_hr_mask = ~isnan(T.ble_hr) & T.ble_hr > 0;
scatter(T.time(ble_hr_mask), T.ble_hr(ble_hr_mask), 18, C_BLUE, 'filled', ...
    'MarkerFaceAlpha', 0.6, 'DisplayName', 'BLE HR');
hold on;

% Plot reference HR
ref_hr_mask = ~isnan(T.ref_hr) & T.ref_hr > 0;
scatter(T.time(ref_hr_mask), T.ref_hr(ref_hr_mask), 40, C_RED, 'd', 'filled', ...
    'MarkerFaceAlpha', 0.9, 'DisplayName', 'Reference HR');

% Shade activity regions
yl = ylim;
label_changes = find(diff([0; double(T.activity_label ~= "")]) ~= 0 | ...
    [true; T.activity_label(2:end) ~= T.activity_label(1:end-1)]);

prev_lbl = "";
for k = 1:numel(label_changes)
    idx = label_changes(k);
    lbl = T.activity_label(idx);
    if lbl == prev_lbl, continue; end
    prev_lbl = lbl;

    % Find end of this label
    end_idx = find(T.activity_label(idx:end) ~= lbl, 1, 'first') + idx - 2;
    if isempty(end_idx), end_idx = height(T); end

    lbl_char = char(lbl);
    if ismember(lbl_char, MOVE_LABELS)
        patch([T.time(idx) T.time(end_idx) T.time(end_idx) T.time(idx)], ...
            [yl(1) yl(1) yl(2) yl(2)], C_ORANGE, ...
            'FaceAlpha', 0.07, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    elseif ismember(lbl_char, FALL_LABELS)
        patch([T.time(idx) T.time(end_idx) T.time(end_idx) T.time(idx)], ...
            [yl(1) yl(1) yl(2) yl(2)], C_RED, ...
            'FaceAlpha', 0.07, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
end

xlabel('Time (s)');
ylabel('Heart Rate (bpm)');
title('Heart Rate: BLE vs Reference', 'FontWeight', 'bold');
legend('Location', 'best', 'Box', 'off');
style_ax(gca);
xlim([0 max(T.time)]);

exportgraphics(fig2, 'fig_hr_timeseries.png', 'Resolution', 300);
fprintf('Saved fig_hr_timeseries.png\n');

%% FIGURE 3: SpO2 time series (BLE vs reference)

fig3 = figure('Position', [100 100 800 320], 'Color', 'w');

ble_spo2_mask = ~isnan(T.ble_spo2) & T.ble_spo2 > 0;
scatter(T.time(ble_spo2_mask), T.ble_spo2(ble_spo2_mask), 18, C_BLUE, 'filled', ...
    'MarkerFaceAlpha', 0.6, 'DisplayName', 'BLE SpO_2');
hold on;

ref_spo2_mask = ~isnan(T.ref_spo2) & T.ref_spo2 > 0;
scatter(T.time(ref_spo2_mask), T.ref_spo2(ref_spo2_mask), 40, C_RED, 'd', 'filled', ...
    'MarkerFaceAlpha', 0.9, 'DisplayName', 'Reference SpO_2');

xlabel('Time (s)');
ylabel('SpO_2 (%)');
title('SpO_2: BLE vs Reference', 'FontWeight', 'bold');
legend('Location', 'best', 'Box', 'off');
style_ax(gca);
xlim([0 max(T.time)]);
ylim([85 105]);

exportgraphics(fig3, 'fig_spo2_timeseries.png', 'Resolution', 300);
fprintf('Saved fig_spo2_timeseries.png\n');

%% FIGURE 4: IMU classification accuracy per activity

fig4 = figure('Position', [100 100 700 420], 'Color', 'w');

acc_vals = [];
acc_labels = {};
acc_colors = [];

for k = 1:height(imu_acc_table)
    if imu_acc_table.Total(k) > 0
        acc_vals(end+1) = imu_acc_table.Correct(k) / imu_acc_table.Total(k) * 100;
        acc_labels{end+1} = char(imu_acc_table.Activity(k));

        lbl_char = char(imu_acc_table.Activity(k));
        if ismember(lbl_char, STILL_LABELS)
            acc_colors(end+1, :) = C_BLUE;
        elseif ismember(lbl_char, MOVE_LABELS)
            acc_colors(end+1, :) = C_ORANGE;
        elseif ismember(lbl_char, FALL_LABELS)
            acc_colors(end+1, :) = C_RED;
        else
            acc_colors(end+1, :) = C_GRAY;
        end
    end
end

bh = barh(acc_vals, 0.6);
bh.FaceColor = 'flat';
bh.CData = acc_colors;
bh.EdgeColor = 'none';

set(gca, 'YTick', 1:numel(acc_labels), 'YTickLabel', acc_labels, 'YDir', 'reverse');
xlabel('Classification Accuracy (%)');
title('IMU Activity Classification Accuracy', 'FontWeight', 'bold');
xlim([0 110]);
style_ax(gca);

% Add percentage labels
for k = 1:numel(acc_vals)
    text(acc_vals(k) + 1.5, k, sprintf('%.0f%%', acc_vals(k)), ...
        'FontSize', 9, 'FontName', fig_font, 'Color', [.3 .3 .3], ...
        'VerticalAlignment', 'middle');
end

exportgraphics(fig4, 'fig_imu_accuracy.png', 'Resolution', 300);
fprintf('Saved fig_imu_accuracy.png\n');

%% FIGURE 5: IMU confusion matrix heatmap

fig5 = figure('Position', [100 100 700 500], 'Color', 'w');

% Normalise rows to percentages
conf_pct = confusion_counts ./ max(sum(confusion_counts, 2), 1) * 100;

imagesc(conf_pct);
colormap(flipud(bone));  % clean grayscale, dark = high
cb = colorbar;
cb.Label.String = '% of packets';
cb.Label.FontSize = fig_fontsize;
caxis([0 100]);

set(gca, 'XTick', 1:numel(all_imu_states), 'XTickLabel', all_imu_states, ...
    'XTickLabelRotation', 45, ...
    'YTick', 1:numel(imu_labels), 'YTickLabel', imu_labels);
xlabel('Reported IMU State');
ylabel('Protocol Activity');
title('IMU State Distribution per Activity', 'FontWeight', 'bold');
style_ax(gca);

% Overlay count text
for r = 1:size(confusion_counts, 1)
    for c = 1:size(confusion_counts, 2)
        if confusion_counts(r, c) > 0
            txt_col = [1 1 1] * (conf_pct(r,c) > 50) * 0.0 + ...
                      [1 1 1] * (conf_pct(r,c) <= 50) * 0.15;
            if conf_pct(r,c) > 50
                txt_col = [1 1 1];
            else
                txt_col = [.15 .15 .15];
            end
            text(c, r, sprintf('%d', confusion_counts(r, c)), ...
                'HorizontalAlignment', 'center', 'FontSize', 9, ...
                'FontName', fig_font, 'Color', txt_col);
        end
    end
end

exportgraphics(fig5, 'fig_imu_confusion.png', 'Resolution', 300);
fprintf('Saved fig_imu_confusion.png\n');

%% FIGURE 6: Bland-Altman plot for HR

fig6 = figure('Position', [100 100 500 400], 'Color', 'w');

if numel(hr_errors) >= 3
    % Recompute paired means for x-axis
    hr_means = [];
    hr_diffs = [];
    for k = 1:numel(labels_all)
        lbl = labels_all(k);
        mask = T.activity_label == lbl;
        m_ble = mean(T.ble_hr(mask & ~isnan(T.ble_hr) & T.ble_hr > 0), 'omitnan');
        m_ref = mean(T.ref_hr(mask & ~isnan(T.ref_hr) & T.ref_hr > 0), 'omitnan');
        if ~isnan(m_ble) && ~isnan(m_ref)
            hr_means(end+1) = (m_ble + m_ref) / 2;
            hr_diffs(end+1) = m_ble - m_ref;
        end
    end

    scatter(hr_means, hr_diffs, 50, C_BLUE, 'filled', 'MarkerFaceAlpha', 0.7);
    hold on;

    mean_diff = mean(hr_diffs);
    sd_diff = std(hr_diffs);
    xl = xlim;

    yline(mean_diff, '-', sprintf('Bias: %.1f', mean_diff), ...
        'Color', [.3 .3 .3], 'LineWidth', 1.2, 'FontSize', 9, ...
        'LabelHorizontalAlignment', 'left');
    yline(mean_diff + 1.96*sd_diff, '--', '+1.96 SD', ...
        'Color', C_RED, 'LineWidth', 1, 'FontSize', 9, ...
        'LabelHorizontalAlignment', 'left');
    yline(mean_diff - 1.96*sd_diff, '--', '-1.96 SD', ...
        'Color', C_RED, 'LineWidth', 1, 'FontSize', 9, ...
        'LabelHorizontalAlignment', 'left');

    xlabel('Mean HR (bpm)');
    ylabel('BLE HR - Reference HR (bpm)');
    title('Bland-Altman: Heart Rate', 'FontWeight', 'bold');
    style_ax(gca);

    exportgraphics(fig6, 'fig_hr_bland_altman.png', 'Resolution', 300);
    fprintf('Saved fig_hr_bland_altman.png\n');
else
    fprintf('Skipping Bland-Altman (not enough paired data).\n');
    close(fig6);
end

%% SUMMARY TABLE (copy-paste for report)

fprintf('  SUMMARY\n');
fprintf('  HR  MAE overall:   %.2f bpm\n', mae_hr_overall);
fprintf('  SpO2 MAE overall:  %.2f %%\n', mae_spo2_overall);
fprintf('  IMU accuracy:      %.1f%%\n', imu_accuracy);

fprintf('\nDone. Figures saved to current directory.\n');

%%  FIGURES

fig_font = 'Helvetica';
fig_fontsize = 11;

% Helper to style axes consistently
    function style_ax(ax)
        set(ax, 'FontName', fig_font, 'FontSize', fig_fontsize, ...
            'Box', 'off', 'TickDir', 'out', 'LineWidth', 0.8, ...
            'Color', 'w', 'XColor', [.2 .2 .2], 'YColor', [.2 .2 .2]);
    end
    