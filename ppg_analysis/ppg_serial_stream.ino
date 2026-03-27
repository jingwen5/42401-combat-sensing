// ppg_serial_stream.ino

#include <Wire.h>
#include <MAX30105.h>

MAX30105 sensor;

void setup() {
  Serial.begin(115200);
  delay(2000);

  // PPG init
  if (!sensor.begin(Wire, 400000)) {
    Serial.println("MAX30102 not found");
    while (1) {}
  }

  sensor.setup(
    60,   // LED power
    4,    // sample average
    2,    // red + IR
    100,  // sample rate
    411,  // pulse width
    4096  // ADC range
  );

  Serial.println("PPG ready.");
}

void loop() {
  int n = sensor.check();

  while (n--) {
    uint32_t ir_raw  = sensor.getFIFOIR();
    uint32_t red_raw = sensor.getFIFORed();

    // Serial output for ppg_serial.py: IR,RED
    Serial.print(ir_raw);
    Serial.print(",");
    Serial.println(red_raw);
  }
}