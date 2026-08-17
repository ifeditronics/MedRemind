#include "ButtonManager.h"

ButtonManager::ButtonManager(uint8_t pinBtn1, uint8_t pinBtn2, uint8_t pinBtn3) {
    btn1 = { pinBtn1, HIGH, HIGH, 0, 0, false, 0, false, false, false, false };
    btn2 = { pinBtn2, HIGH, HIGH, 0, 0, false, 0, false, false, false, false };
    btn3 = { pinBtn3, HIGH, HIGH, 0, 0, false, 0, false, false, false, false };
}

void ButtonManager::init() {
    pinMode(btn1.pin, INPUT_PULLUP);
    pinMode(btn2.pin, INPUT_PULLUP);
    pinMode(btn3.pin, INPUT_PULLUP);
}

void ButtonManager::updateButton(ButtonState& btn, bool supportLongPress, bool supportAutoRepeat) {
    bool raw = digitalRead(btn.pin);
    unsigned long now = millis();

    // Lockout debouncing: only allow stableState changes if the lockout window has expired
    if (now - btn.lastDebounceTime >= DEBOUNCE_DELAY) {
        if (raw != btn.stableState) {
            btn.stableState = raw;
            btn.lastDebounceTime = now; // Reset lockout timer on transition

            if (btn.stableState == LOW) {
                // Button Pressed
                btn.pressStartTime = now;
                btn.longPressedTriggered = false;
                btn.repeatActive = false;
                btn.lastRepeatTime = now;

                if (!supportLongPress) {
                    btn.shortPressPending = true; // Trigger immediately on press for BTN1, BTN2
                }
            } else {
                // Button Released
                if (supportLongPress) {
                    if (!btn.longPressedTriggered) {
                        btn.shortPressPending = true; // Trigger on release for BTN3 ONLY if not long pressed
                    }
                }
                btn.repeatActive = false;
            }
        }
    }

    // Held states are processed independently of the debounce lockout window, 
    // ensuring auto-repeat and long-press timers operate accurately.
    if (btn.stableState == LOW) {
        if (supportLongPress && !btn.longPressedTriggered) {
            if (now - btn.pressStartTime >= LONG_PRESS_TIME) {
                btn.longPressedTriggered = true;
                btn.longPressPending = true;
            }
        }

        if (supportAutoRepeat) {
            if (!btn.repeatActive) {
                if (now - btn.pressStartTime >= AUTO_REPEAT_DELAY) {
                    btn.repeatActive = true;
                    btn.lastRepeatTime = now;
                    btn.repeatPressPending = true;
                }
            } else {
                if (now - btn.lastRepeatTime >= AUTO_REPEAT_RATE) {
                    btn.lastRepeatTime = now;
                    btn.repeatPressPending = true;
                }
            }
        }
    }

    btn.lastRawState = raw;
}

void ButtonManager::update() {
    updateButton(btn1, false, true);  // BTN1: No long press, auto-repeat
    updateButton(btn2, false, true);  // BTN2: No long press, auto-repeat
    updateButton(btn3, true, false);  // BTN3: Long press, no auto-repeat
}

bool ButtonManager::checkBtn1Pressed() {
    if (btn1.shortPressPending || btn1.repeatPressPending) {
        btn1.shortPressPending = false;
        btn1.repeatPressPending = false;
        return true;
    }
    return false;
}

bool ButtonManager::checkBtn2Pressed() {
    if (btn2.shortPressPending || btn2.repeatPressPending) {
        btn2.shortPressPending = false;
        btn2.repeatPressPending = false;
        return true;
    }
    return false;
}

bool ButtonManager::checkBtn3ShortPressed() {
    if (btn3.shortPressPending) {
        btn3.shortPressPending = false;
        return true;
    }
    return false;
}

bool ButtonManager::checkBtn3LongPressed() {
    if (btn3.longPressPending) {
        btn3.longPressPending = false;
        return true;
    }
    return false;
}
