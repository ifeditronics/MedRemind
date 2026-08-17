#include "AlarmManager.h"

AlarmManager::AlarmManager(uint8_t pinBuzzer)
    : buzzerPin(pinBuzzer), active(false), activeDose(0) {}

void AlarmManager::init() {
    pinMode(buzzerPin, OUTPUT);
    stop();
}

void AlarmManager::start(uint8_t dose) {
    active = true;
    activeDose = dose;
    update();
}

void AlarmManager::stop() {
    active = false;
    activeDose = 0;
    update();
}

void AlarmManager::update() {
    // If alarm is active, set the buzzer pin HIGH (continuous sound).
    // Otherwise, set it LOW.
    digitalWrite(buzzerPin, active ? HIGH : LOW);
}
