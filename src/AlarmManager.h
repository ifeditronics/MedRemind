#ifndef ALARM_MANAGER_H
#define ALARM_MANAGER_H

#include <Arduino.h>

class AlarmManager {
private:
    uint8_t buzzerPin;
    bool active;
    uint8_t activeDose;

public:
    AlarmManager(uint8_t pinBuzzer);
    void init();
    void start(uint8_t dose);
    void stop();
    void update(); // Synchronizes the physical pin with state

    bool isActive() const { return active; }
    uint8_t getActiveDose() const { return activeDose; }
};

#endif // ALARM_MANAGER_H
