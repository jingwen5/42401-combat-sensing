%% Load data

Test = readtable('data/eval_est_loc_a.csv'); % Estimated (BLE)
Tref = readtable('data/eval_ref_loc_a.csv'); % Reference (finger)

%% Get windows

win_ids = unique(Test.window);
num_windows = length(win_ids);

est_hr = nan(num_windows,1);
est_spo2 = nan(num_windows,1);

true_hr = nan(num_windows,1);
true_spo2 = nan(num_windows,1);

%% Compute per-window values

for k = 1:num_windows
    w = win_ids(k);

    % Estimated values for this window
    Te = Test(Test.window == w, :);

    if height(Te) > 0
        est_hr(k) = median(Te.estimated_hr, 'omitnan');
        est_spo2(k) = median(Te.estimated_spo2, 'omitnan');
    end

    % Reference values for this window
    Tr = Tref(Tref.window == w, :);

    if height(Tr) > 0
        true_hr(k) = median(Tr.true_hr, 'omitnan');
        true_spo2(k) = median(Tr.true_spo2, 'omitnan');
    end
end

%% Compute errors

hr_err = est_hr - true_hr;
spo2_err = est_spo2 - true_spo2;

mae_hr = mean(abs(hr_err), 'omitnan');
mae_spo2 = mean(abs(spo2_err), 'omitnan');

disp(['MAE HR = ', num2str(mae_hr), ' bpm'])
disp(['MAE SpO2 = ', num2str(mae_spo2), ' %'])

%% Plot HR comparison

figure
plot(win_ids, true_hr, 'k-o', 'LineWidth', 1.5)
hold on
plot(win_ids, est_hr, 'r-s', 'LineWidth', 1.5)
xlabel('Window')
ylabel('Heart Rate (bpm)')
title(sprintf('HR Comparison (MAE = %.2f bpm)', mae_hr))
legend('True HR', 'Estimated HR')
grid on

%% Plot SpO2 comparison

figure
plot(win_ids, true_spo2, 'k-o', 'LineWidth', 1.5)
hold on
plot(win_ids, est_spo2, 'b-s', 'LineWidth', 1.5)
xlabel('Window')
ylabel('SpO2 (%)')
title(sprintf('SpO2 Comparison (MAE = %.2f %%)', mae_spo2))
legend('True SpO2', 'Estimated SpO2')
grid on