#ifndef BUTTON_MANAGER_H
#define BUTTON_MANAGER_H

#include <Arduino.h>

struct ButtonState {
    uint8_t pin;
    bool lastRawState;
    bool stableState;
    unsigned long lastDebounceTime;
    unsigned long pressStartTime;
    bool longPressedTriggered;
    unsigned long lastRepeatTime;
    bool repeatActive;
    bool shortPressPending;
    bool longPressPending;
    bool repeatPressPending; // Set to true when an auto-repeat press occurs
};

class ButtonManager {
private:
    ButtonState btn1;
    ButtonState btn2;
    ButtonState btn3;

    static const unsigned long DEBOUNCE_DELAY = 50; // ms
    static const unsigned long LONG_PRESS_TIME = 1000; // ms
    static const unsigned long AUTO_REPEAT_DELAY = 500; // ms
    static const unsigned long AUTO_REPEAT_RATE = 120; // ms

    void updateButton(ButtonState& btn, bool supportLongPress, bool supportAutoRepeat);

public:
    ButtonManager(uint8_t pinBtn1, uint8_t pinBtn2, uint8_t pinBtn3);
    void init();
    void update(); // Call in loop()

    bool checkBtn1Pressed();
    bool checkBtn2Pressed();
    bool checkBtn3ShortPressed();
    bool checkBtn3LongPressed();
};

#endif // BUTTON_MANAGER_H
