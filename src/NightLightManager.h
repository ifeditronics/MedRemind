#ifndef NIGHT_LIGHT_MANAGER_H
#define NIGHT_LIGHT_MANAGER_H

#include <Arduino.h>

class NightLightManager {
private:
    uint8_t pin1;
    uint8_t pin2;
    bool isOnState;

public:
    NightLightManager(uint8_t pinLed1, uint8_t pinLed2);
    void init();
    void toggle();
    void set(bool on);
    bool isOn() const;
};

#endif // NIGHT_LIGHT_MANAGER_H
