#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Arduino.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>
#include "ClockManager.h"
#include "MedicationManager.h"

// =====================================================
// TFT ST7735S 128x128 Pin Configuration
// =====================================================

#define TFT_CS    4
#define TFT_DC    18
#define TFT_RST   14
#define TFT_MOSI  20
#define TFT_SCLK  19

// =====================================================
// DISPLAY MANAGER
// =====================================================

class DisplayManager
{
private:

    // -------------------------------------------------
    // TFT
    // -------------------------------------------------

    Adafruit_ST7735 tft;

    // -------------------------------------------------
    // Drawing helper
    // -------------------------------------------------

    void drawTwoDigit(uint8_t value);



public:

    // =================================================
    // Constructor / Initialization
    // =================================================

    DisplayManager();

    void init();

    // =================================================
    // Mode-specific screen drawing
    //
    // Full-screen redraws are only performed when
    // entering/changing a major UI mode.
    // =================================================

    void drawClockScreen(
        const ClockManager& clock,
        const MedicationSchedule& nextMed
    );

    void drawSetAlarmScreen(
        uint8_t setupMode,
        const MedicationSchedule& med
    );

    void drawMedicationAlarmScreen(
        const MedicationSchedule& med
    );

    void drawConfirmationScreen(
        const MedicationSchedule& med
    );

    // =================================================
    // Flicker-free partial updates
    //
    // These functions update only the required region.
    // =================================================

    void updateClockTime(
        const ClockManager& clock
    );

    void updateClockColon(
        bool visible
    );

    void updateClockDate(
        const ClockManager& clock
    );

    void updateNextMedicationInfo(
        const MedicationSchedule& nextMed
    );

    void updateHourglass(int frame);
};

#endif // DISPLAY_MANAGER_H