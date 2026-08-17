#ifndef BLE_MANAGER_H
#define BLE_MANAGER_H

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

class BLEManager {
private:
    BLEServer* pServer;
    BLECharacteristic* pTimeSyncChar;
    BLECharacteristic* pStatusConfigChar;
    bool connected;
    bool lastConnectedState;

    // Time Sync pending data
    volatile bool timeSyncPending;
    uint8_t syncDay, syncMonth;
    uint16_t syncYear;
    uint8_t syncHour, syncMinute, syncSecond, syncWeekday;

    // Medication Config pending data
    volatile bool medConfigPending;
    uint8_t cfgId;
    uint8_t cfgHour, cfgMinute, cfgDose;
    bool cfgActive;

public:
    BLEManager();
    void init();
    void update(); // Handles advertising restart on disconnect

    // Checking pending operations (called in loop())
    bool checkTimeSyncPending(uint8_t& day, uint8_t& month, uint16_t& year,
                              uint8_t& hour, uint8_t& minute, uint8_t& second,
                              uint8_t& weekday);
                              
    bool checkMedConfigPending(uint8_t& id, uint8_t& hour, uint8_t& minute,
                               uint8_t& dose, bool& active);

    // Notifications and Status
    void notifyMedicationEvent(uint8_t statusCode); // 0 = idle, 1 = alarm active, 2 = ack, 3 = taken
    bool isConnected() const { return connected; }

    // Internal Callback handlers
    void handleConnect();
    void handleDisconnect();
    void handleTimeSyncWrite(uint8_t* data, size_t length);
    void handleStatusConfigWrite(uint8_t* data, size_t length);
};

#endif // BLE_MANAGER_H
