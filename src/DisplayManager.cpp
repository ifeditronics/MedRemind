#include "DisplayManager.h"

DisplayManager::DisplayManager()
    : tft(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST)
{
}

void DisplayManager::init()
{
    tft.initR(INITR_144GREENTAB);
    tft.setRotation(0);
}

void DisplayManager::drawTwoDigit(uint8_t value)
{
    if (value < 10)
    {
        tft.print("0");
    }
    tft.print(value);
}

// 12x14 animated hourglass frames (2 bytes per row, 14 rows)
const unsigned char hourglass_frames[5][28] PROGMEM = {
    // Frame 0: Full top, empty bottom
    {
        0xFF, 0xF0, // ############
        0xFF, 0xF0, // ##########
        0x7F, 0xE0, // .########.
        0x3F, 0xC0, // ..######..
        0x1F, 0x80, // ...####...
        0x0F, 0x00, // ....##....
        0x06, 0x00, // .....##.....
        0x06, 0x00, // .....##.....
        0x09, 0x00, // ....#..#....
        0x10, 0x80, // ...#....#...
        0x20, 0x40, // ..#......#..
        0x40, 0x20, // .#........#.
        0x80, 0x10, // #..........#
        0xFF, 0xF0  // ############
    },
    // Frame 1: Mostly top, stream, tiny bottom pile
    {
        0xFF, 0xF0,
        0x80, 0x10,
        0x7F, 0xE0,
        0x3F, 0xC0,
        0x1F, 0x80,
        0x0F, 0x00,
        0x06, 0x00,
        0x06, 0x00,
        0x09, 0x00,
        0x10, 0x80,
        0x20, 0x40,
        0x43, 0x20,
        0x87, 0x90,
        0xFF, 0xF0
    },
    // Frame 2: Half top, stream, medium bottom pile
    {
        0xFF, 0xF0,
        0x80, 0x10,
        0x40, 0x20,
        0x3F, 0xC0,
        0x1F, 0x80,
        0x0F, 0x00,
        0x06, 0x00,
        0x06, 0x00,
        0x09, 0x00,
        0x10, 0x80,
        0x23, 0xC0,
        0x47, 0xE0,
        0x8F, 0xF0,
        0xFF, 0xF0
    },
    // Frame 3: Little top, stream, large bottom pile
    {
        0xFF, 0xF0,
        0x80, 0x10,
        0x40, 0x20,
        0x20, 0x40,
        0x1F, 0x80,
        0x0F, 0x00,
        0x06, 0x00,
        0x06, 0x00,
        0x09, 0x00,
        0x13, 0x80,
        0x27, 0xC0,
        0x4F, 0xE0,
        0x8F, 0xF0,
        0xFF, 0xF0
    },
    // Frame 4: Empty top, no stream, full bottom pile
    {
        0xFF, 0xF0,
        0x80, 0x10,
        0x40, 0x20,
        0x20, 0x40,
        0x10, 0x80,
        0x09, 0x00,
        0x06, 0x00,
        0x06, 0x00,
        0x0F, 0x00,
        0x1F, 0x80,
        0x3F, 0xC0,
        0x7F, 0xE0,
        0xFF, 0xF0,
        0xFF, 0xF0
    }
};

void DisplayManager::drawClockScreen(const ClockManager& clock, const MedicationSchedule& nextMed) {
    tft.fillScreen(ST77XX_BLACK);

    // Draw static header: "Remember your Drug" (White, size 1)
    tft.setTextColor(ST77XX_WHITE);
    tft.setTextSize(1);
    tft.setCursor(10, 5);
    tft.print("Remember your Drug");

    // Render contents (dynamic but drawn once at transition)
    updateNextMedicationInfo(nextMed);
    
    // Draw initial hourglass frame (derive frame from second)
    int currentFrame = (clock.getSecond() * 5) / 60;
    updateHourglass(currentFrame);

    updateClockTime(clock);
    updateClockDate(clock);
}

void DisplayManager::updateClockTime(const ClockManager& clock) {
    // Large 12-hour HH:MM display centered horizontally (x = 19, y = 56)
    tft.setTextColor(ST77XX_GREEN, ST77XX_BLACK);
    tft.setTextSize(3);
    tft.setCursor(19, 56);
    drawTwoDigit(clock.get12Hour());
    tft.print(":");
    drawTwoDigit(clock.getMinute());

    // Display smaller AM/PM centered horizontally under the digits (x = 58, y = 84)
    tft.setTextColor(ST77XX_GREEN, ST77XX_BLACK);
    tft.setTextSize(1);
    tft.setCursor(58, 84);
    tft.print(clock.isPM() ? "PM" : "AM");
}

void DisplayManager::updateClockColon(bool visible) {
    // Only toggle the colon character region (x = 55, y = 56)
    tft.setTextSize(3);
    tft.setCursor(55, 56);
    if (visible) {
        tft.setTextColor(ST77XX_GREEN, ST77XX_BLACK);
    } else {
        tft.setTextColor(ST77XX_BLACK, ST77XX_BLACK);
    }
    tft.print(":");
}

void DisplayManager::updateClockDate(const ClockManager& clock) {
    // Format date string (e.g. "Mon, 17 Aug, 2026")
    char dateBuf[24];
    snprintf(dateBuf, sizeof(dateBuf), "%s, %02d %s, %04d", 
             clock.getWeekdayName(), clock.getDay(), clock.getMonthName(), clock.getYear());

    // Center and draw the date (x dynamically calculated, y = 105)
    int dateLen = strlen(dateBuf);
    int dateX = (128 - (dateLen * 6)) / 2;
    if (dateX < 0) dateX = 0;

    tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
    tft.setTextSize(1);
    tft.setCursor(dateX, 105);
    tft.print(dateBuf);
}

void DisplayManager::updateNextMedicationInfo(const MedicationSchedule& nextMed) {
    tft.setTextSize(1);
    
    // Clear and draw the medication time and dose area with black background
    tft.setCursor(10, 20);
    if (nextMed.active) {
        tft.setTextColor(ST77XX_GREEN, ST77XX_BLACK);
        tft.print("Time: ");
        uint8_t hr12 = nextMed.hour % 12;
        if (hr12 == 0) hr12 = 12;
        drawTwoDigit(hr12);
        tft.print(":");
        drawTwoDigit(nextMed.minute);
        tft.print(nextMed.hour >= 12 ? " PM" : " AM");
        tft.print("   "); // Clear trailing characters
        
        tft.setCursor(10, 32);
        tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
        tft.print("Doses: ");
        tft.print(nextMed.dose);
        tft.print("   ");
    } else {
        tft.setTextColor(ST77XX_GREEN, ST77XX_BLACK);
        tft.print("Time: --:--   ");
        
        tft.setCursor(10, 32);
        tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
        tft.print("Doses: - ");
    }
}

void DisplayManager::updateHourglass(int frame) {
    if (frame < 0 || frame > 4) return;
    
    // Clear only the 12x14 hourglass region (at x = 106, y = 20)
    tft.fillRect(106, 20, 12, 14, ST77XX_BLACK);
    
    // Draw the new frame
    tft.drawBitmap(106, 20, hourglass_frames[frame], 12, 14, ST77XX_GREEN);
}

void DisplayManager::drawSetAlarmScreen(uint8_t setupMode, const MedicationSchedule& med) {
    static uint8_t lastSetupMode = 0;

    // Full screen refresh when entering setup mode
    if (lastSetupMode == 0 || (setupMode == 1 && lastSetupMode == 3)) {
        tft.fillScreen(ST77XX_BLACK);
        
        // Static Header (White, size 1)
        tft.setTextColor(ST77XX_WHITE);
        tft.setTextSize(1);
        tft.setCursor(10, 5);
        tft.print("Set Medication");
        
        // Static Row Labels
        tft.setCursor(10, 25);
        tft.print("Time:    ");
        
        tft.setCursor(10, 37);
        tft.print("Doses:   ");
        
        // =====================================================
        // Static Reminder Message
        // =====================================================

        tft.setTextColor(ST77XX_ORANGE);
        tft.setTextSize(1);

        const char* note1 = "Please, take drugs";
        const char* note2 = " prscribd by your Dr.";

        int x1 = (128 - (strlen(note1) * 6)) / 2;
        int x2 = (128 - (strlen(note2) * 6)) / 2;

        tft.setCursor(x1, 62);
        tft.print(note1);

        tft.setCursor(x2, 73);
        tft.print(note2);


        // =====================================================
        // Static Control Hints
        // =====================================================

        // IMPORTANT: Switch back to WHITE
        tft.setTextColor(ST77XX_WHITE);
        tft.setTextSize(1);

        // Keep both controls together as one line
        const char* controls = " BTN1 +    BTN2 -";

        int controlsX = (128 - (strlen(controls) * 6)) / 2;

        tft.setCursor(controlsX, 105);
        tft.print(controls);
    }

    // Determine field colors (Green only for selected field, otherwise White)
    uint16_t hourColor   = (setupMode == 1) ? ST77XX_GREEN : ST77XX_WHITE;
    uint16_t minuteColor = (setupMode == 2) ? ST77XX_GREEN : ST77XX_WHITE;
    uint16_t doseColor   = (setupMode == 3) ? ST77XX_GREEN : ST77XX_WHITE;

    // --- 1. Render Time Values ---
    uint8_t displayHour = med.hour % 12;
    if (displayHour == 0) displayHour = 12;

    tft.setTextSize(1);

    // Overwrite hour digits in-place
    tft.setCursor(64, 25);
    tft.setTextColor(hourColor, ST77XX_BLACK);
    drawTwoDigit(displayHour);

    // Overwrite colon in-place
    tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
    tft.print(":");

    // Overwrite minute digits in-place
    tft.setTextColor(minuteColor, ST77XX_BLACK);
    drawTwoDigit(med.minute);

    // Overwrite AM/PM in-place
    tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
    tft.print(med.hour >= 12 ? " PM" : " AM");

    // --- 2. Render Dose Values ---
    // Overwrite dose digits in-place
    tft.setCursor(64, 37);
    tft.setTextColor(doseColor, ST77XX_BLACK);
    tft.print(med.dose);
    tft.print("   "); // Clear trailing characters

    // --- 3. Render Bottom Instructions ---
    tft.setCursor(10, 90);
    tft.setTextColor(ST77XX_WHITE, ST77XX_BLACK);
    if (setupMode == 3) {
        tft.print("  BTN3: SAVE");
    } else {
        tft.print("  BTN3: NEXT");
    }

    lastSetupMode = setupMode;
}

void DisplayManager::drawMedicationAlarmScreen(const MedicationSchedule& med) {
    tft.fillScreen(ST77XX_BLACK);

    // Header
    tft.setTextColor(ST77XX_YELLOW);
    tft.setTextSize(1);
    tft.setCursor(19, 25);
    tft.print("MEDICATION TIME");

    // Divider
    tft.drawFastHLine(0, 42, 128, ST77XX_YELLOW);

    // Dose information (Dominant)
    tft.setTextColor(ST77XX_WHITE);
    tft.setTextSize(2);
    tft.setCursor(28, 58);
    tft.print("DOSE ");
    tft.print(med.dose);

    // Instructions
    tft.setTextSize(1);
    tft.setCursor(34, 95);
    tft.print("PRESS BTN3");
    tft.setCursor(22, 110);
    tft.print("TO ACKNOWLEDGE");
}

void DisplayManager::drawConfirmationScreen(const MedicationSchedule& med) {
    tft.fillScreen(ST77XX_BLACK);

    tft.setTextColor(ST77XX_GREEN);
    tft.setTextSize(1);
    tft.setCursor(22, 25);
    tft.print("DOSE ");
    tft.print(med.dose);
    tft.print(" TAKEN?");

    // Divider
    tft.drawFastHLine(0, 42, 128, ST77XX_GREEN);

    tft.setTextColor(ST77XX_WHITE);
    tft.setTextSize(1);
    tft.setCursor(16, 75);
    tft.print("PRESS BTN3 AGAIN");
    tft.setCursor(34, 95);
    tft.print("TO CONFIRM");
}