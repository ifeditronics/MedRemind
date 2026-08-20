#include "ClockManager.h"

ClockManager::ClockManager()
    : currentHour(12), currentMinute(0), currentSecond(0),
      currentDay(17), currentMonth(8), currentYear(2026), currentWeekday(1),
      currentEpoch(1781700000), // Corresponds to Aug 17, 2026
      lastSecondMillis(0), secondChangedFlag(false), minuteChangedFlag(false), dateChangedFlag(false) {}

void ClockManager::init() {
    lastSecondMillis = millis();
}

uint8_t ClockManager::daysInMonth(uint8_t month, uint16_t year) const {
    switch (month) {
        case 2:
            if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
                return 29;
            }
            return 28;
        case 4:
        case 6:
        case 9:
        case 11:
            return 30;
        default:
            return 31;
    }
}

void ClockManager::advanceDate() {
    currentDay++;
    if (currentDay > daysInMonth(currentMonth, currentYear)) {
        currentDay = 1;
        currentMonth++;
        if (currentMonth > 12) {
            currentMonth = 1;
            currentYear++;
        }
    }
    currentWeekday++;
    if (currentWeekday > 6) {
        currentWeekday = 0;
    }
    dateChangedFlag = true;
}

void ClockManager::update() {
    unsigned long now = millis();
    // Handles rollover safely by subtraction
    if (now - lastSecondMillis >= 1000) {
        lastSecondMillis += 1000;
        currentSecond++;
        currentEpoch++;
        secondChangedFlag = true;

        if (currentSecond >= 60) {
            currentSecond = 0;
            currentMinute++;
            minuteChangedFlag = true;

            if (currentMinute >= 60) {
                currentMinute = 0;
                currentHour++;

                if (currentHour >= 24) {
                    currentHour = 0;
                    advanceDate();
                }
            }
        }
    }
}

void ClockManager::setDateTime(uint32_t epoch, uint8_t day, uint8_t month, uint16_t year,
                               uint8_t hour, uint8_t minute, uint8_t second,
                               uint8_t weekday) {
    currentEpoch = epoch;
    currentDay = day;
    currentMonth = month;
    currentYear = year;
    currentHour = hour;
    currentMinute = minute;
    currentSecond = second;
    currentWeekday = weekday;
    lastSecondMillis = millis();
    
    // Trigger redraw flags
    secondChangedFlag = true;
    minuteChangedFlag = true;
    dateChangedFlag = true;
}

bool ClockManager::checkSecondChanged() {
    if (secondChangedFlag) {
        secondChangedFlag = false;
        return true;
    }
    return false;
}

bool ClockManager::checkMinuteChanged() {
    if (minuteChangedFlag) {
        minuteChangedFlag = false;
        return true;
    }
    return false;
}

bool ClockManager::checkDateChanged() {
    if (dateChangedFlag) {
        dateChangedFlag = false;
        return true;
    }
    return false;
}

const char* ClockManager::getWeekdayName() const {
    switch (currentWeekday) {
        case 0: return "SUN";
        case 1: return "MON";
        case 2: return "TUE";
        case 3: return "WED";
        case 4: return "THU";
        case 5: return "FRI";
        case 6: return "SAT";
        default: return "";
    }
}

const char* ClockManager::getMonthName() const {
    switch (currentMonth) {
        case 1:  return "JAN";
        case 2:  return "FEB";
        case 3:  return "MAR";
        case 4:  return "APR";
        case 5:  return "MAY";
        case 6:  return "JUN";
        case 7:  return "JUL";
        case 8:  return "AUG";
        case 9:  return "SEP";
        case 10: return "OCT";
        case 11: return "NOV";
        case 12: return "DEC";
        default: return "";
    }
}

bool ClockManager::isPM() const {
    return currentHour >= 12;
}

uint8_t ClockManager::get12Hour() const {
    uint8_t hr = currentHour % 12;
    return (hr == 0) ? 12 : hr;
}
