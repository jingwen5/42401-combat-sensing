% run imu_find_thresholds.m first to get the stats in the proper arrays

% Constants - trimmed to only the ones we're using
BUF_SIZE = 200;
DEV_BUFFER_SIZE = 50;
CHECK_TRIGGER = 1.4;
IDLE_TRIGGER = 0.85;
ACCEL_DEV_THRESHOLD = 0.08;
GYRO_DEV_THRESHOLD = 17.1;
TILT_TRIGGER_ANGLE = 30;

% labels in group_labels array

n = length(group_labels); % expected events
num_tags = length(tags);

ECS = EVENT_CLASSIFICATION_SUMMARY;
corresponding_states = ["DETECTED_FALL" "RUNNING" "WALKING" "WALKING" "JUMPING_OR_QUICK_SIT" "JUMPING_OR_QUICK_SIT" "JUMPING_OR_QUICK_SIT"];
tag_to_state_map = [tags' corresponding_states'];

% stats
tag_stats = struct();
for i = 1:num_tags
    tag_stats.(tags(i)) = struct("NUM_TESTS", 0, "NUM_CORRECT", 0, "PERCENT_CORRECT", 0.0, "WRONG_EVENTS", []);
end


% get calculated state vs. expected state stats using reported value
for i = 1:n
    label_idx = find(tags == group_labels(i));
    etag = group_labels(i);
    tag_stats.(etag).NUM_TESTS = tag_stats.(etag).NUM_TESTS + 1;
    % match!
    if(ECS(i, 1) == corresponding_states(label_idx))
        tag_stats.(etag).NUM_CORRECT = tag_stats.(etag).NUM_CORRECT + 1;
    % add misidentified events to an array
    else
        tag_stats.(etag).WRONG_EVENTS = [tag_stats.(etag).WRONG_EVENTS ECS(i,1)];
    end
end

for i = 1:num_tags
    tag_stats.(tags(i)).PERCENT_CORRECT = 100*tag_stats.(tags(i)).NUM_CORRECT / tag_stats.(tags(i)).NUM_TESTS;
    disp(tags(i));
    disp(tag_stats.(tags(i)));
end

