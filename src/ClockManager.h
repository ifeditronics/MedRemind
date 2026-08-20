#ifndef CLOCK_MANAGER_H
#define CLOCK_MANAGER_H

#include <Arduino.h>

class ClockManager {
private:
    uint8_t currentHour;
    uint8_t currentMinute;
    uint8_t currentSecond;
    uint8_t currentDay;
    uint8_t currentMonth;
    uint16_t currentYear;
    uint8_t currentWeekday; // 0 = Sunday, 1 = Monday, ...
    uint32_t currentEpoch;

    unsigned long lastSecondMillis;
    bool secondChangedFlag;
    bool minuteChangedFlag;
    bool dateChangedFlag;

    uint8_t daysInMonth(uint8_t month, uint16_t year) const;
    void advanceDate();

public:
    ClockManager();
    void init();
    void update(); // Should be called in loop() continuously

    // Setters
    void setDateTime(uint32_t epoch, uint8_t day, uint8_t month, uint16_t year,
                     uint8_t hour, uint8_t minute, uint8_t second,
                     uint8_t weekday);

    // Getters
    uint8_t getHour() const { return currentHour; }
    uint8_t getMinute() const { return currentMinute; }
    uint8_t getSecond() const { return currentSecond; }
    uint8_t getDay() const { return currentDay; }
    uint8_t getMonth() const { return currentMonth; }
    uint16_t getYear() const { return currentYear; }
    uint8_t getWeekday() const { return currentWeekday; }
    uint32_t getEpoch() const { return currentEpoch; }

    bool checkSecondChanged(); // Returns true once when second changes, resets flag
    bool checkMinuteChanged(); // Returns true once when minute changes, resets flag
    bool checkDateChanged();   // Returns true once when date changes, resets flag

    const char* getWeekdayName() const;
    const char* getMonthName() const;
    bool isPM() const;
    uint8_t get12Hour() const;
};

#endif // CLOCK_MANAGER_H
