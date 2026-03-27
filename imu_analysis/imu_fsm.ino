// imu_fsm.ino
#include "LSM6DS3.h"
#include "Wire.h"
#include <bluefruit.h>
#include <math.h>

// DEBUGGING MACROS
#define DEBUG_ANGLE 1

// constants
const float G = 9.81;
const float RAD_TO_DEG_CONV = 57.295779;
const bool USE_BLE = false;
// macros

// should run at 100Hz
#define LOOP_DELAY 10 

// These values are inspired by the paper
#define BUF_SIZE 200
#define IDLE_TRIGGER 0.8
#define CHECK_TRIGGER 1.4

// These values are inspired by the data
#define ACCEL_DEV_THRESHOLD 0.08 // 0.1 in the paper, 0.0845 max from data
#define GYRO_DEV_THRESHOLD 17.1 // 10 in the paper, 17ish from data
#define DEV_BUFFER_SIZE 50 // same as paper

// Thresholds for detecting walking or running, from the data
#define ACCEL_DEV_WALKING 0.13
#define ACCEL_DEV_RUNNING 0.702
#define ASVM_RUN_WALK_THRESHOLD 2.6
#define BUF_SMALL 50 // calculate these things over a smaller buffer to improve responsiveness
#define PEAK_BUF_SIZE 10

// relative comparison, check if final - init angle is greater than the threshold
#define TILT_TRIGGER 30

#define STATIONARY_THRESHOLD 0.15


// Note: the AY value is actually the "AZ" due to the orientation of the device lol

// BLE UART service
BLEUart bleuart;

//Create a instance of class LSM6DS3
LSM6DS3 myIMU(I2C_MODE, 0x6A);    //I2C device address 0x6A


double cal_gx = 1.101100;
double cal_gy = -2.472750;
double cal_gz = 0.921550;

double cal_ax = -0.058177;
double cal_ay = -0.020211;
double cal_az = -0.001846;

// buffers for holding window of data
float gx_buf[BUF_SIZE];
float gy_buf[BUF_SIZE];
float gz_buf[BUF_SIZE];

float ax_buf[BUF_SIZE];
float ay_buf[BUF_SIZE];
float az_buf[BUF_SIZE];

float asvm_buf[BUF_SIZE];
float gsvm_buf[BUF_SIZE];

int update_pos;
int check_pos;
int max_pos;
bool avg_valid;

float A_SVM_mean;
float G_SVM_mean;

struct curr_vals_struct {
    float ax;
    float ay;
    float az;
    float gx;
    float gy;
    float gz;
    float A_SVM; // signal vector magnitude
    float G_SVM;
    uint32_t curr_time;
    uint32_t delta_time;
    float fall_impact;
    float fall_event_val;
};

curr_vals_struct cv = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false};

// motion classifer states, sorry for the bad naming
enum FALL_STATES {
    IDLE_FALL = 0,
    CHECK_FALL = 1,
    ANALYZE_IMPACT = 2,
    DETECTED_FALL = 3,
    STATIONARY_POST_FALL = 4,
    WALKING = 5,
    RUNNING = 6,
    JUMPING_OR_QUICK_SIT = 7
} fall_state;

String fall_state_strings[9] = {"IDLE_FALL", "CHECK_FALL", "ANALYZE_IMPACT", "DETECTED_FALL", "STATIONARY_POST_FALL", "WALKING", "RUNNING", "JUMPING_OR_QUICK_SIT"};

enum IMU_COMP {
    ACCEL = 0,
    GYRO = 1
} imu_comp;

// reset stuff to 0s
void initialize_values() {
    fall_state = IDLE_FALL;
    cv.A_SVM = 0.0;
    cv.G_SVM = 0.0;
    update_pos = 0;
    check_pos = 0;
    max_pos = 0;
    avg_valid = false;
}

// update values in the buffers
void update_values(bool update_buffers) {
    // read from the IMU
    cv.ax = myIMU.readFloatAccelX() - cal_ax;
    cv.ay = myIMU.readFloatAccelY() - cal_ay;
    cv.az = myIMU.readFloatAccelZ() - cal_az;

    cv.gx = myIMU.readFloatGyroX() - cal_gx;
    cv.gy = myIMU.readFloatGyroY() - cal_gy;
    cv.gz = myIMU.readFloatGyroZ() - cal_gz;

    // update SVMs
    cv.A_SVM = sqrt(sq(cv.ax) + sq(cv.ay) + sq(cv.az));
    cv.G_SVM = sqrt(sq(cv.gx) + sq(cv.gy) + sq(cv.gz));

    // update buffers with new value
    if(update_buffers) {
        ax_buf[update_pos] = cv.ax;
        ay_buf[update_pos] = cv.ay;
        az_buf[update_pos] = cv.az;

        gx_buf[update_pos] = cv.gx;
        gy_buf[update_pos] = cv.gy;
        gz_buf[update_pos] = cv.gz;

        // might not need
        asvm_buf[update_pos] = cv.A_SVM;
        gsvm_buf[update_pos] = cv.G_SVM;

        // increment position pointer
        update_pos = (update_pos + 1) % BUF_SIZE;

        // update means
        A_SVM_mean = (A_SVM_mean*(update_pos - 1))/(update_pos) + (cv.A_SVM)/(update_pos);
        G_SVM_mean = (G_SVM_mean*(update_pos - 1))/(update_pos) + (cv.G_SVM)/(update_pos);

        // update if the data is valid or not
        if(!avg_valid & (update_pos >= BUF_SIZE)) {
            avg_valid = true;
        }
    }
    
}

// for debugging
void print_values() {
    Serial.print("AX: "); Serial.print(cv.ax); Serial.print(", ");
    Serial.print("AY: "); Serial.print(cv.ay); Serial.print(", ");
    Serial.print("AZ: "); Serial.print(cv.az); Serial.print(", ");

    Serial.print("GX: "); Serial.print(cv.gx); Serial.print(", ");
    Serial.print("GY: "); Serial.print(cv.gy); Serial.print(", ");
    Serial.print("GZ: "); Serial.print(cv.gz); Serial.print(", ");

    Serial.print("ASVM: "); Serial.print(cv.A_SVM); Serial.print(", ");
    Serial.print("GSVM: "); Serial.print(cv.G_SVM); Serial.print(", ");

    Serial.print("FALL_EVENT: "); Serial.print(cv.fall_event_val); Serial.print(", ");
    Serial.print("STATE: "); Serial.println(fall_state);
}

// Send only critical values over BLE:
// MCU_time, fall_state if in {DETECTED_FALL, STATIONARY_POST_FALL, 
// WALKING, RUNNING, JUMPING_OR_QUICK_SIT}, fall impact in Gs
void send_values_BLE() {
    update_values(1);

    char buffer[160];

    cv.delta_time = millis() - cv.curr_time; // very naive, optimize later
    cv.curr_time = cv.curr_time + cv.delta_time;

    // send time and motion information
    snprintf(buffer, sizeof(buffer),
            ",%.lu,%.3f,%.3f",
            cv.delta_time, cv.fall_event_val, cv.fall_impact);
    Serial.println(buffer);
    bleuart.print(buffer);
}

// send values over serial - use for testing to send all data points to analyze
void send_values_serial() {

    update_values(1);
    char buffer[160];

    cv.delta_time = millis() - cv.curr_time; // very naive, optimize later
    cv.curr_time = cv.curr_time + cv.delta_time;

    // send accel values
    snprintf(buffer, sizeof(buffer),
            "%.3f,%.3f,%.3f",
            cv.ax, cv.ay, cv.az);
    Serial.print(buffer);

    // send gyro values
    snprintf(buffer, sizeof(buffer),
            ",%.3f,%.3f,%.3f",
            cv.gx, cv.gy, cv.gz);
    Serial.print(buffer);

    // send svm values
    snprintf(buffer, sizeof(buffer),
            ",%.3f,%.3f",
            cv.A_SVM, cv.G_SVM);
    Serial.print(buffer);
      // send time and fall_event values
    snprintf(buffer, sizeof(buffer),
            ",%.lu,%.3f,",
            cv.delta_time, cv.fall_event_val);
    Serial.print(buffer);
    Serial.println(fall_state_strings[fall_state]);
}

// send values over BLE or serial
void send_values() {
    if(USE_BLE) {
        send_values_BLE();
    }
    else {
        send_values_serial();
    }
}
// returns if there was a high acceleration event, also collect the BUF_SIZE
// samples for later processing
bool check_fall() {
    bool large_accel = false;
    // reset update position
    update_pos = 0;
    check_pos = 0;
    max_pos = 0;
    float max_accel = 0;
    for(int i = 0; i < BUF_SIZE; i++) {
        // update_values(1);
        send_values();
        if(cv.A_SVM >= CHECK_TRIGGER) {
            if(!large_accel) {
                check_pos = i; // save index of first suprathreshold ASVM only
            }
            large_accel = true; // found at least one suprathreshold ASVM
        }
        // also update a maximum acceleration for later use
        if(cv.A_SVM >= max_accel) {
            max_accel = cv.A_SVM;
            max_pos = i; // also save index of max accel value
        }
        delay(LOOP_DELAY); // delay since collecting samples
    }

    cv.fall_impact = max_accel;
    return large_accel;
}

// Calculate stdev over the last DEV_BUFFER_SIZE samples of the buffer
// If doesn't work, consider doing a comparison between earlier samples
// and later samples to show stabilization
float std_dev_check(IMU_COMP dev_type, int buffer_size) {
    float mean = 0.0;
    int start_idx = 0;
    int end_idx = 0;
    if(buffer_size == BUF_SIZE) {
        start_idx = BUF_SIZE - DEV_BUFFER_SIZE;
        end_idx = BUF_SIZE;
        buffer_size = DEV_BUFFER_SIZE;
    }
    else {
        start_idx = 0;
        end_idx = buffer_size;
    }
    // naive implementation, optimize if lag is too bad
    for(int i = start_idx; i < end_idx; i++) {
        float val = (dev_type == ACCEL) ? asvm_buf[i] : gsvm_buf[i];
        mean = mean + val;
    }
    
    mean = mean/buffer_size;

    float variance = 0.0;

    for(int i = start_idx; i < end_idx; i++) {
        float val = (dev_type == ACCEL) ? asvm_buf[i] : gsvm_buf[i];
        variance = variance + (val - mean)*(val-mean);

    }

    variance = variance/buffer_size;
    
    return sqrt(variance);
    
}

// fix this so it stops returning NaN lol
bool posture_check() {
    float tilt_init_sum = 0.0;
    float tilt_final_sum = 0.0;
    float hor_dist = 0.0;

    // extremely naive implementation, optimize later
    for(int i = 0; i < check_pos; i++) {
        hor_dist = sqrt(ax_buf[i]*ax_buf[i] + az_buf[i]*az_buf[i]);
        tilt_init_sum += atan2(ay_buf[i], hor_dist);
    }

    int end_idx = min(BUF_SIZE, max_pos + BUF_SMALL);
    
    for(int i = max_pos; i < end_idx; i++) {
        hor_dist = sqrt(ax_buf[i]*ax_buf[i] + az_buf[i]*az_buf[i]);
        tilt_final_sum += atan2(ay_buf[i], hor_dist);
    }

    float avg_init = (RAD_TO_DEG_CONV*tilt_init_sum) / (check_pos);
    float avg_final = (RAD_TO_DEG_CONV*tilt_final_sum) / (end_idx - max_pos);

    if(DEBUG_ANGLE) {
        Serial.print("******* init: "); Serial.println(avg_init);
        Serial.print("******* final: "); Serial.println(avg_final);
        Serial.print("******* check_pos: "); Serial.println(check_pos);
        Serial.print("******* max_pos: "); Serial.println(max_pos);
        Serial.print("******* max accel: "); Serial.println(cv.fall_impact);
        Serial.print("******* end_idx: "); Serial.println(end_idx);
        Serial.print("******* end_idx - max_pos: "); Serial.println(end_idx - max_pos);
    }

    float tilt_diff = (fabs(avg_final - avg_init));
    cv.fall_event_val = tilt_diff;
    Serial.print("Calculated angle: "); Serial.print(tilt_diff); Serial.print(", TILT_TRIGGER: "); Serial.println(TILT_TRIGGER);
    return (tilt_diff >= TILT_TRIGGER);
}

// basically the same as update_values(1) but only updates the buffers
// until a certain buffer_size
void update_buffer(int buffer_size) {
    // reset update position
    update_pos = 0;
    for(int i = 0; i < buffer_size; i++) {
        update_values(1);
    }
    return;
}

// check if person is stationary (low ASVM)
bool check_stationary() {
    bool stationary = false;
    float sum = 0.0;
    for(int i = 0; i < BUF_SMALL; i++) {
        sum = sum + asvm_buf[i];
    }

    float avg_asvm = sum / BUF_SMALL;
    cv.fall_event_val = avg_asvm;
    // ASVM = 1 when stationary
    stationary = (abs(avg_asvm - 1) <= STATIONARY_THRESHOLD);
    return stationary;
}

// score based next_state generation instead of all-or-nothing logic
// calculate event score based on closeness to each event's thresholds, lowest
// score "wins" and is the classified event
// if all scores are too high then go to IDLE
int calculate_event() {
    next_state = IDLE_FALL; // default
    
    return next_state;
}


void setup() {
    Serial.begin(115200);
    while (!Serial);
    if (myIMU.begin() != 0) {
        Serial.println("Device error");
    } else {
        Serial.println("Device OK!");
    }

    // BLE init
    Bluefruit.begin();
    Bluefruit.setName("XIAO-IMU");

    bleuart.begin();

    Bluefruit.Advertising.addService(bleuart);
    Bluefruit.Advertising.addName();
    Bluefruit.Advertising.start(0); // continuous

    initialize_values();
}

// FSM style motion detection
void loop() {
    if(fall_state == IDLE_FALL) {
        // Serial.println("IN IDLE_FALL");
        send_values();
        cv.fall_event_val = 0.0;
        // right now this is just a instantaneous check but really should 
        // be some small running average
        if(cv.A_SVM <= IDLE_TRIGGER) {
            fall_state = CHECK_FALL;
        }
        else {
            fall_state = IDLE_FALL;
        }
    }

    if(fall_state == CHECK_FALL) {
        send_values();
        Serial.println("IN CHECK_FALL");
        // collect buffer of samples and send
        if(check_fall()) {
            fall_state = ANALYZE_IMPACT;
        }
        else {
            fall_state = IDLE_FALL;
        }
    }

    // analyze values from the buffer to classify the motion
    if(fall_state == ANALYZE_IMPACT) {
        send_values();
        Serial.println("IN ANALYZE_IMPACT");
        float std_accel = std_dev_check(ACCEL, BUF_SIZE);
        float std_gyro = std_dev_check(GYRO, BUF_SIZE);
        bool fall_tilt_check = posture_check();
        bool stabilized_dev =   (std_accel <= ACCEL_DEV_THRESHOLD) &&
                                (std_accel <= GYRO_DEV_THRESHOLD);
        bool walking_dev =  (std_accel >= ACCEL_DEV_WALKING) &&
                            (std_accel <= ACCEL_DEV_RUNNING);
        bool running_dev =  (std_accel >= ACCEL_DEV_RUNNING);
        bool running_accel = (cv.fall_impact >= ASVM_RUN_WALK_THRESHOLD);
        
        // Fall
        if(stabilized_dev && fall_tilt_check) {
            fall_state = DETECTED_FALL;
        }
        // Run
        else if(running_dev && !fall_tilt_check && running_accel) {
            fall_state = RUNNING;
        }
        // Walk
        else if(walking_dev && !fall_tilt_check && !running_accel) {
            fall_state = WALKING;
        }
        // Jump or sit
        else if(stabilized_dev && !fall_tilt_check) {
            fall_state = JUMPING_OR_QUICK_SIT;
        }
        // Something else??
        else {
            fall_state = IDLE_FALL;
        }
    }

    if(fall_state == DETECTED_FALL) {
        Serial.println("IN DETECTED_FALL");
        cv.fall_event_val = 1.0; // toggle fall signal and send
        send_values();
        cv.fall_event_val = 0.0;

        // check if stationary post fall
        update_buffer(BUF_SMALL);
        if(check_stationary()) {
            fall_state = STATIONARY_POST_FALL;
        }
        else {
            // go back to IDLE if moving again
            initialize_values();
            fall_state = IDLE_FALL;
        }
    }

    if(fall_state == STATIONARY_POST_FALL) {
        Serial.println("IN STATIONARY_POST_FALL");
        send_values();
        update_buffer(BUF_SMALL);
        // stay in this state if still unmoving
        if(check_stationary()) {
            fall_state = STATIONARY_POST_FALL;
        }
        // return to idle when moving again
        else {
            initialize_values();
            fall_state = IDLE_FALL;
        }
    }

    // walking and running is ok so just go back to IDLE
    // Add limp detection here
    if(fall_state == WALKING || fall_state == RUNNING) {
        Serial.println("WALKING OR RUNNING");
        send_values();
        fall_state = IDLE_FALL;
    }

    // jumping and sitting is also ok
    if(fall_state == JUMPING_OR_QUICK_SIT) {
        Serial.println("IN JUMPING_OR_QUICK_SIT");
        send_values();
        fall_state = IDLE_FALL;
    }

    delay(LOOP_DELAY);
}