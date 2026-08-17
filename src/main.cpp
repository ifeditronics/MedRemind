#include <Arduino.h>
#include "ClockManager.h"
#include "DisplayManager.h"
#include "ButtonManager.h"
#include "MedicationManager.h"
#include "AlarmManager.h"
#include "NightLightManager.h"
#include "BLEManager.h"

// =====================================================
// PIN ASSIGNMENTS
// =====================================================

#define BUZZER_PIN        5
#define NIGHT_LIGHT_1_PIN 6
#define NIGHT_LIGHT_2_PIN 7
#define BUTTON1_PIN       1
#define BUTTON2_PIN       2
#define BUTTON3_PIN       3

// =====================================================
// GLOBAL OBJECTS
// =====================================================

ClockManager clockMgr;
DisplayManager displayMgr;
ButtonManager buttonMgr(BUTTON1_PIN, BUTTON2_PIN, BUTTON3_PIN);
MedicationManager medMgr;
AlarmManager alarmMgr(BUZZER_PIN);
NightLightManager nightLightMgr(NIGHT_LIGHT_1_PIN, NIGHT_LIGHT_2_PIN);
BLEManager bleMgr;

// =====================================================
// STATE MACHINE VARIABLES
// =====================================================

enum DeviceMode {
    MODE_CLOCK,
    MODE_SET_ALARM_HOUR,
    MODE_SET_ALARM_MINUTE,
    MODE_SET_DOSE,
    MODE_MEDICATION_ALARM,
    MODE_CONFIRM_MEDICATION
};

DeviceMode deviceMode = MODE_CLOCK;
MedicationSchedule nextMed;
MedicationSchedule cachedNextMed;

// =====================================================
// SETUP
// =====================================================

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("Smart Medication Reminder System starting...");

    // Initialize Managers
    nightLightMgr.init();
    alarmMgr.init();
    buttonMgr.init();
    medMgr.init();
    clockMgr.init();
    displayMgr.init();
    bleMgr.init();

    // Cache the next upcoming medication schedule
    nextMed = medMgr.getNextMedication(clockMgr.getHour(), clockMgr.getMinute());
    cachedNextMed = nextMed;

    // Draw initial standby clock screen
    displayMgr.drawClockScreen(clockMgr, nextMed);
}

// =====================================================
// LOOP
// =====================================================

void loop() {
    // 1. Process Background Tasks
    clockMgr.update();
    buttonMgr.update();
    bleMgr.update();
    alarmMgr.update();

    // 2. Handle Night Light (BTN3 Long Press)
    if (buttonMgr.checkBtn3LongPressed()) {
        nightLightMgr.toggle();
        Serial.printf("Night light toggled. State: %s\n", nightLightMgr.isOn() ? "ON" : "OFF");
    }

    // 3. Handle BLE Time Synchronization
    uint8_t syncDay, syncMonth, syncHour, syncMinute, syncSecond, syncWeekday;
    uint16_t syncYear;
    if (bleMgr.checkTimeSyncPending(syncDay, syncMonth, syncYear, syncHour, syncMinute, syncSecond, syncWeekday)) {
        clockMgr.setDateTime(syncDay, syncMonth, syncYear, syncHour, syncMinute, syncSecond, syncWeekday);
        Serial.println("Clock synchronized with phone time via BLE.");
        
        // Notify BLE client that time sync succeeded
        bleMgr.notifyMedicationEvent(0x05); // 0x05 = TIME_SYNC_ACK
        
        // Force refresh of the standby display if we are active
        if (deviceMode == MODE_CLOCK) {
            nextMed = medMgr.getNextMedication(clockMgr.getHour(), clockMgr.getMinute());
            cachedNextMed = nextMed;
            displayMgr.drawClockScreen(clockMgr, nextMed);
        }
    }

    // 4. Handle BLE Medication Configuration Updates
    uint8_t cfgId, cfgHour, cfgMinute, cfgDose;
    bool cfgActive;
    if (bleMgr.checkMedConfigPending(cfgId, cfgHour, cfgMinute, cfgDose, cfgActive)) {
        medMgr.addOrUpdateSchedule(cfgId, cfgHour, cfgMinute, cfgDose, cfgActive);
        Serial.printf("Medication schedule %d updated via BLE.\n", cfgId);
        
        // Force update of next medication info if in clock mode
        if (deviceMode == MODE_CLOCK) {
            nextMed = medMgr.getNextMedication(clockMgr.getHour(), clockMgr.getMinute());
            cachedNextMed = nextMed;
            displayMgr.updateNextMedicationInfo(nextMed);
        }
    }

    // 5. Handle Medication Alarm Triggering
    static bool alarmTriggeredForThisMinute = false;
    if (deviceMode == MODE_CLOCK) {
        if (nextMed.active) {
            if (clockMgr.getHour() == nextMed.hour && 
                clockMgr.getMinute() == nextMed.minute && 
                clockMgr.getSecond() == 0) {
                
                if (!alarmTriggeredForThisMinute) {
                    alarmTriggeredForThisMinute = true;
                    deviceMode = MODE_MEDICATION_ALARM;
                    
                    // Sound Buzzer & Switch UI
                    alarmMgr.start(nextMed.dose);
                    displayMgr.drawMedicationAlarmScreen(nextMed);
                    
                    // Notify Mobile App
                    bleMgr.notifyMedicationEvent(0x01); // 0x01 = Alarm Active
                }
            } else {
                alarmTriggeredForThisMinute = false;
            }
        }
    }

    // 6. Handle Standby Display Updates (Flicker-Free, No fillRect/fillScreen)
    if (deviceMode == MODE_CLOCK) {
        static int lastFrame = -1;

        bool minChanged = clockMgr.checkMinuteChanged();
        if (minChanged) {
            displayMgr.updateClockTime(clockMgr);
        }

        // Second tick updates
        if (clockMgr.checkSecondChanged()) {
            if (!minChanged) {
                displayMgr.updateClockColon(clockMgr.getSecond() % 2 == 0);
            }
            
            // Hourglass animation frame (1 minute loop, 5 frames, 12s per frame)
            int currentFrame = (clockMgr.getSecond() * 5) / 60;
            if (currentFrame != lastFrame) {
                lastFrame = currentFrame;
                displayMgr.updateHourglass(currentFrame);
            }
        }

        // Redraw date only when date shifts (at midnight)
        if (clockMgr.checkDateChanged()) {
            displayMgr.updateClockDate(clockMgr);
        }

        // Check if next medication has changed (e.g. day roll-over, sync, or setting edit)
        nextMed = medMgr.getNextMedication(clockMgr.getHour(), clockMgr.getMinute());
        if (nextMed.hour != cachedNextMed.hour || 
            nextMed.minute != cachedNextMed.minute || 
            nextMed.dose != cachedNextMed.dose || 
            nextMed.active != cachedNextMed.active || 
            nextMed.id != cachedNextMed.id) {
            
            cachedNextMed = nextMed;
            displayMgr.updateNextMedicationInfo(nextMed);
        }
    }

    // 7. Handle Button Input State Machine Transitions
    switch (deviceMode) {
        case MODE_CLOCK:
            if (buttonMgr.checkBtn3ShortPressed()) {
                deviceMode = MODE_SET_ALARM_HOUR;
                MedicationSchedule* pMed = medMgr.getScheduleByIndex(0);
                displayMgr.drawSetAlarmScreen(1, *pMed); // 1 = Set Hour Mode
            }
            break;

        case MODE_SET_ALARM_HOUR:
            {
                MedicationSchedule* pMed = medMgr.getScheduleByIndex(0);
                if (buttonMgr.checkBtn1Pressed()) {
                    pMed->hour = (pMed->hour + 1) % 24;
                    displayMgr.drawSetAlarmScreen(1, *pMed);
                } else if (buttonMgr.checkBtn2Pressed()) {
                    pMed->hour = (pMed->hour == 0) ? 23 : pMed->hour - 1;
                    displayMgr.drawSetAlarmScreen(1, *pMed);
                } else if (buttonMgr.checkBtn3ShortPressed()) {
                    deviceMode = MODE_SET_ALARM_MINUTE;
                    displayMgr.drawSetAlarmScreen(2, *pMed); // 2 = Set Minute Mode
                }
            }
            break;

        case MODE_SET_ALARM_MINUTE:
            {
                MedicationSchedule* pMed = medMgr.getScheduleByIndex(0);
                if (buttonMgr.checkBtn1Pressed()) {
                    pMed->minute = (pMed->minute + 1) % 60;
                    displayMgr.drawSetAlarmScreen(2, *pMed);
                } else if (buttonMgr.checkBtn2Pressed()) {
                    pMed->minute = (pMed->minute == 0) ? 59 : pMed->minute - 1;
                    displayMgr.drawSetAlarmScreen(2, *pMed);
                } else if (buttonMgr.checkBtn3ShortPressed()) {
                    deviceMode = MODE_SET_DOSE;
                    displayMgr.drawSetAlarmScreen(3, *pMed); // 3 = Set Dose Mode
                }
            }
            break;

        case MODE_SET_DOSE:
            {
                MedicationSchedule* pMed = medMgr.getScheduleByIndex(0);
                if (buttonMgr.checkBtn1Pressed()) {
                    if (pMed->dose < 99) pMed->dose++;
                    displayMgr.drawSetAlarmScreen(3, *pMed);
                } else if (buttonMgr.checkBtn2Pressed()) {
                    if (pMed->dose > 1) pMed->dose--;
                    displayMgr.drawSetAlarmScreen(3, *pMed);
                } else if (buttonMgr.checkBtn3ShortPressed()) {
                    pMed->active = true;
                    deviceMode = MODE_CLOCK;
                    
                    // Force refresh standby screen
                    nextMed = medMgr.getNextMedication(clockMgr.getHour(), clockMgr.getMinute());
                    cachedNextMed = nextMed;
                    displayMgr.drawClockScreen(clockMgr, nextMed);
                }
            }
            break;

        case MODE_MEDICATION_ALARM:
            if (buttonMgr.checkBtn3ShortPressed()) {
                alarmMgr.stop();
                deviceMode = MODE_CONFIRM_MEDICATION;
                displayMgr.drawConfirmationScreen(nextMed);
                bleMgr.notifyMedicationEvent(0x02); // 0x02 = Acknowledged
            }
            break;

        case MODE_CONFIRM_MEDICATION:
            if (buttonMgr.checkBtn3ShortPressed()) {
                deviceMode = MODE_CLOCK;
                bleMgr.notifyMedicationEvent(0x03); // 0x03 = Confirmed Taken
                
                // Recalculate next upcoming medication and draw clock screen
                nextMed = medMgr.getNextMedication(clockMgr.getHour(), clockMgr.getMinute());
                cachedNextMed = nextMed;
                displayMgr.drawClockScreen(clockMgr, nextMed);
            }
            break;
    }

    // Small delay to yield CPU and prevent high-power consumption
    delay(5);
}