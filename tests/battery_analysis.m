% Read CSVs
charge = readtable('data/battery_log_charge.csv');
drain = readtable('data/battery_log_drain.csv');

% Convert datetime strings to elapsed seconds
charge_t = seconds(datetime(charge.datetime) - datetime(charge.datetime(1)));
drain_t = seconds(datetime(drain.datetime) - datetime(drain.datetime(1)));

% Battery percent function
bat_pct = @(v) (v >= 3.5) .* (7 + (v - 3.5) ./ (4.2 - 3.5) * 93) + ...
               (v < 3.5)  .* ((v - 2.5) ./ (3.5 - 2.5) * 7);

charge_pct = floor(bat_pct(charge.vbat));
drain_pct = floor(bat_pct(drain.vbat));

% Estimate charge time (find where vbat plateaus near max)
charge_threshold = 0.99 * max(charge.vbat);
charge_end_idx = find(charge.vbat >= charge_threshold, 1, 'first');
charge_time_hr = charge_t(charge_end_idx) / 3600;

% Estimate drain time (find where vbat plateaus near min)
drain_threshold = 1.01 * min(drain.vbat) + 0.01;
drain_end_idx = find(drain.vbat <= drain_threshold, 1, 'first');
drain_time_hr = drain_t(drain_end_idx) / 3600;

fprintf('Charge time: %.2f hours (%.0f seconds)\n', charge_time_hr, charge_t(charge_end_idx));
fprintf('Drain time: %.2f hours (%.0f seconds)\n', drain_time_hr, drain_t(drain_end_idx));

% Figure 1: Drain
figure;
subplot(2,1,1);
plot(drain_t, drain.vbat, 'r');
xlabel('Time (s)'); ylabel('Vbat (V)');
% title(sprintf('Drain - Voltage (%.1f hrs)', drain_time_hr));
grid on;

subplot(2,1,2);
plot(drain_t, drain_pct, 'r');
xlabel('Time (s)'); ylabel('Battery (%)');
% title(sprintf('Drain - Percent (%.1f hrs)', drain_time_hr));
grid on;

% Figure 2: Charge
figure;
subplot(2,1,1);
plot(charge_t, charge.vbat, 'b');
xlabel('Time (s)'); ylabel('Vbat (V)');
% title(sprintf('Charge - Voltage (%.1f hrs)', charge_time_hr));
grid on;

subplot(2,1,2);
plot(charge_t, charge_pct, 'b');
xlabel('Time (s)'); ylabel('Battery (%)');
% title(sprintf('Charge - Percent (%.1f hrs)', charge_time_hr));
grid on;
