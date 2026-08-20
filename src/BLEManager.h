#ifndef BLE_MANAGER_H
#define BLE_MANAGER_H

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>

struct MedicationEvent {
    uint32_t eventId;
    uint8_t scheduleId;
    uint8_t scheduledHour;
    uint8_t scheduledMinute;
    uint8_t dose;
    uint8_t status;
    uint8_t source;
    uint8_t scheduledYearOffset;
    uint8_t scheduledMonth;
    uint8_t scheduledDay;
};

class BLEManager {
private:
    BLEServer* pServer;
    BLECharacteristic* pTimeSyncChar;
    BLECharacteristic* pStatusConfigChar;
    BLE2902* pStatusConfigDescriptor;
    bool connected;
    bool lastConnectedState;

    unsigned long connectionTime;
    bool disconnectDetected;
    unsigned long disconnectTime;

    // Time Sync pending data
    volatile bool timeSyncPending;
    uint32_t syncTimestamp;
    uint8_t syncDay, syncMonth;
    uint16_t syncYear;
    uint8_t syncHour, syncMinute, syncSecond, syncWeekday;

    // Medication Config pending data
    volatile bool medConfigPending;
    uint8_t cfgId;
    uint8_t cfgHour, cfgMinute, cfgDose;
    bool cfgActive;

    // Persistent Event Queue
    static const uint8_t MAX_UNSENT_EVENTS = 10;
    MedicationEvent unsentEvents[MAX_UNSENT_EVENTS];
    uint8_t unsentCount;
    Preferences preferences;

    void saveEvents();
    void loadEvents();

public:
    BLEManager();
    void init();
    void update(); // Handles advertising restart and event retransmission

    // Checking pending operations (called in loop())
    bool checkTimeSyncPending(uint32_t& timestamp, uint8_t& day, uint8_t& month, uint16_t& year,
                              uint8_t& hour, uint8_t& minute, uint8_t& second,
                              uint8_t& weekday);
                              
    bool checkMedConfigPending(uint8_t& id, uint8_t& hour, uint8_t& minute,
                               uint8_t& dose, bool& active);

    // Event queue management
    void addMedicationEvent(uint8_t scheduleId, uint8_t scheduledHour, uint8_t scheduledMinute,
                            uint8_t dose, uint8_t source, uint8_t yearOffset,
                            uint8_t month, uint8_t day, uint32_t epoch);

    // Notifications and Status
    void notifyMedicationEvent(uint8_t statusCode); // 0 = idle, 1 = alarm active, 2 = ack, 3 = taken
    void notifyMedicationConfig(uint8_t id, uint8_t hour, uint8_t minute, uint8_t dose, bool active);
    void notifyMedicationEventRecord(const MedicationEvent& event);
    
    bool isConnected() const { return connected; }
    bool isReadyToNotify() const;

    // Internal Callback handlers
    void handleConnect();
    void handleDisconnect();
    void handleTimeSyncWrite(uint8_t* data, size_t length);
    void handleStatusConfigWrite(uint8_t* data, size_t length);
};

#endif // BLE_MANAGER_H
