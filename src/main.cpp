#include <Arduino.h>
#include <Arduino_LSM6DSOX.h>
#include <ArduinoBLE.h>

const char* const SERVICE_UUID        = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const char* const CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

BLEService gestureService(SERVICE_UUID);
BLEStringCharacteristic gestureCharacteristic(CHARACTERISTIC_UUID, BLENotify, 20);

float last_y = 0.0f;

// STATE MACHINE NON BLOCK
unsigned long globalLockoutEnd = 0;
unsigned long actionTimer      = 0;
unsigned long lastSampleTime   = 0;
bool pendingProcess            = false;

int tapCount  = 0;
int fistCount = 0;

const unsigned long WINDOW_WAIT_MS = 600; // PROCESS
const unsigned long LOCKOUT_MS     = 450; // ANTI DOUBLE TRIGGER

void setup() {
    Serial.begin(115200);
    if (!IMU.begin()) { while (1); }
    if (!BLE.begin()) { while (1); }

    BLE.setLocalName("Wearable_Gesture_Controller");
    BLE.setAdvertisedService(gestureService);
    gestureService.addCharacteristic(gestureCharacteristic);
    BLE.addService(gestureService);
   
    BLE.advertise();
    Serial.println("V10 VER");
}

void loop() {
    BLE.poll(); // STABILITY BLE
    
    BLEDevice central = BLE.central();
    if (central && central.connected()) {
        unsigned long currentTime = millis();

        // 104 Hz Hardware Sampling Lock
        if (currentTime - lastSampleTime >= 10) {
            lastSampleTime = currentTime;

            float x, y, z;
            if (IMU.accelerationAvailable()) {
                IMU.readAcceleration(x, y, z);
                
                // DELTA DIFFERSIAL TEMPORAL
                float delta_y = y - last_y;
                last_y = y; 
                
                float abs_delta_y = abs(delta_y);

                // RUNNING
                if (currentTime > globalLockoutEnd) {
                    
                    // 1. FIST
                    if (abs_delta_y >= 0.2f && abs_delta_y < 0.4f) {
                        fistCount++;
                        Serial.print("-> (FIST) | Delta Y: ");
                        Serial.println(abs_delta_y);
                        
                        if (fistCount == 1) {
                            actionTimer = currentTime;
                            pendingProcess = true;
                        }
                        globalLockoutEnd = currentTime + 340;
                    }
                    
                    // 2. TAP
                    else if (abs_delta_y >= 0.15f && abs_delta_y < 0.2f) {
                        tapCount++;
                        Serial.print("-> (TAP) | Delta Y: ");
                        Serial.println(abs_delta_y);
                        
                        if (tapCount == 1) {
                            actionTimer = currentTime;
                            pendingProcess = true;
                        }
                        globalLockoutEnd = currentTime + 180; 
                    }
                }
            }
        }

        // 3. BLE STATE
        if (pendingProcess && (millis() - actionTimer > WINDOW_WAIT_MS)) {
            
            if (tapCount == 1 && fistCount == 0) {
                gestureCharacteristic.writeValue("NEXT_TAP");
            } 
            else if (tapCount >= 2 && fistCount == 0) {
                gestureCharacteristic.writeValue("PREV_TAP");
            } 
            else if (fistCount == 1 && tapCount == 0) {
                gestureCharacteristic.writeValue("NEXT_FIST");
            } 
            else if (fistCount >= 2 && tapCount == 0) {
                gestureCharacteristic.writeValue("PREV_FIST");
            }

            // CLEANING
            tapCount = 0;
            fistCount = 0;
            pendingProcess = false;
            globalLockoutEnd = millis() + LOCKOUT_MS; 
        }
    }
}
