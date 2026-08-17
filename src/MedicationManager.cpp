#include "MedicationManager.h"

MedicationManager::MedicationManager() : count(0) {
    for (uint8_t i = 0; i < MAX_MEDICATIONS; i++) {
        schedules[i] = { i, 0, 0, 0, false };
    }
}

void MedicationManager::init() {
    // Initialize with a default schedule: ID 0, 13:00 (1 PM), 1 dose, active
    // This maintains backward compatibility with the original hardware behavior
    addOrUpdateSchedule(0, 13, 0, 1, true);
}

bool MedicationManager::addOrUpdateSchedule(uint8_t id, uint8_t hour, uint8_t minute, uint8_t dose, bool active) {
    // If schedule already exists, update it
    for (uint8_t i = 0; i < count; i++) {
        if (schedules[i].id == id) {
            schedules[i].hour = hour;
            schedules[i].minute = minute;
            schedules[i].dose = dose;
            schedules[i].active = active;
            return true;
        }
    }

    // Add new schedule if space is available
    if (count < MAX_MEDICATIONS) {
        schedules[count] = { id, hour, minute, dose, active };
        count++;
        return true;
    }

    return false;
}

MedicationSchedule MedicationManager::getNextMedication(uint8_t currentHour, uint8_t currentMinute) const {
    MedicationSchedule nextMed = { 255, 0, 0, 0, false };
    int minDiff = 9999;

    for (uint8_t i = 0; i < count; i++) {
        if (!schedules[i].active) continue;

        int diff = (schedules[i].hour * 60 + schedules[i].minute) - (currentHour * 60 + currentMinute);
        
        // If it's <= 0, it means it already passed today or is happening right now, so the NEXT occurrence is tomorrow
        if (diff <= 0) {
            diff += 24 * 60;
        }

        if (diff < minDiff) {
            minDiff = diff;
            nextMed = schedules[i];
        }
    }

    return nextMed;
}

bool MedicationManager::hasActiveMedications() const {
    for (uint8_t i = 0; i < count; i++) {
        if (schedules[i].active) return true;
    }
    return false;
}

MedicationSchedule* MedicationManager::getScheduleByIndex(uint8_t index) {
    if (index < count) {
        return &schedules[index];
    }
    return nullptr;
}
