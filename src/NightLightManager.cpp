#include "NightLightManager.h"

NightLightManager::NightLightManager(uint8_t pinLed1, uint8_t pinLed2)
    : pin1(pinLed1), pin2(pinLed2), isOnState(false) {}

void NightLightManager::init() {
    pinMode(pin1, OUTPUT);
    pinMode(pin2, OUTPUT);
    set(false);
}

void NightLightManager::toggle() {
    set(!isOnState);
}

void NightLightManager::set(bool on) {
    isOnState = on;
    digitalWrite(pin1, isOnState ? HIGH : LOW);
    digitalWrite(pin2, isOnState ? HIGH : LOW);
}

bool NightLightManager::isOn() const {
    return isOnState;
}
