#ifndef MEDICATION_MANAGER_H
#define MEDICATION_MANAGER_H

#include <Arduino.h>

struct MedicationSchedule {
    uint8_t id;
    uint8_t hour;     // 0-23
    uint8_t minute;   // 0-59
    uint8_t dose;     // number of doses
    bool active;      // is enabled
};

class MedicationManager {
private:
    static const uint8_t MAX_MEDICATIONS = 10;
    MedicationSchedule schedules[MAX_MEDICATIONS];
    uint8_t count;

public:
    MedicationManager();
    void init(); // Sets up default schedule

    bool addOrUpdateSchedule(uint8_t id, uint8_t hour, uint8_t minute, uint8_t dose, bool active);
    MedicationSchedule getNextMedication(uint8_t currentHour, uint8_t currentMinute) const;
    bool hasActiveMedications() const;
    
    // Direct getters/setters for on-device single-medication editing
    MedicationSchedule* getScheduleByIndex(uint8_t index);
    uint8_t getCount() const { return count; }
};

#endif // MEDICATION_MANAGER_H
