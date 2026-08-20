#include "BLEManager.h"

#define SERVICE_UUID           "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define TIME_SYNC_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define STATUS_CONFIG_CHAR_UUID "d866a2e2-9b24-44cf-a87d-41a451d6c8b5"

class ServerCallbacks : public BLEServerCallbacks {
private:
    BLEManager* mgr;
public:
    ServerCallbacks(BLEManager* m) : mgr(m) {}
    void onConnect(BLEServer* pServer) override {
        mgr->handleConnect();
    }
    void onDisconnect(BLEServer* pServer) override {
        mgr->handleDisconnect();
    }
};

class TimeSyncCallbacks : public BLECharacteristicCallbacks {
private:
    BLEManager* mgr;
public:
    TimeSyncCallbacks(BLEManager* m) : mgr(m) {}
    void onWrite(BLECharacteristic* pChar) override {
        uint8_t* val = pChar->getData();
        size_t len = pChar->getLength();
        mgr->handleTimeSyncWrite(val, len);
    }
};

class StatusConfigCallbacks : public BLECharacteristicCallbacks {
private:
    BLEManager* mgr;
public:
    StatusConfigCallbacks(BLEManager* m) : mgr(m) {}
    void onWrite(BLECharacteristic* pChar) override {
        uint8_t* val = pChar->getData();
        size_t len = pChar->getLength();
        mgr->handleStatusConfigWrite(val, len);
    }
};

BLEManager::BLEManager()
    : pServer(nullptr), pTimeSyncChar(nullptr), pStatusConfigChar(nullptr),
      pStatusConfigDescriptor(nullptr),
      connected(false), lastConnectedState(false),
      connectionTime(0), disconnectDetected(false), disconnectTime(0),
      timeSyncPending(false),
      syncTimestamp(0), syncDay(0), syncMonth(0), syncYear(0), syncHour(0), syncMinute(0),
      syncSecond(0), syncWeekday(0), medConfigPending(false),
      cfgId(0), cfgHour(0), cfgMinute(0), cfgDose(0), cfgActive(false),
      unsentCount(0) {}

void BLEManager::init() {
    loadEvents();
    // 1. Initialize BLE device
    BLEDevice::init("MedRemind");

    // 2. Create Server
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks(this));

    // 3. Create Service
    BLEService* pService = pServer->createService(SERVICE_UUID);

    // 4. Create Time Sync Characteristic (Write Only)
    pTimeSyncChar = pService->createCharacteristic(
        TIME_SYNC_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pTimeSyncChar->setCallbacks(new TimeSyncCallbacks(this));

    // 5. Create Status Config Characteristic (Read/Write/Notify)
    pStatusConfigChar = pService->createCharacteristic(
        STATUS_CONFIG_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pStatusConfigChar->setCallbacks(new StatusConfigCallbacks(this));
    
    // Save pointer to the BLE2902 descriptor
    pStatusConfigDescriptor = new BLE2902();
    pStatusConfigChar->addDescriptor(pStatusConfigDescriptor);

    // 6. Start Service
    pService->start();

    // 7. Start Advertising
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[DIAGNOSTIC] BLE Server initialized and advertising.");
}

void BLEManager::update() {
    // Non-blocking advertising restart on client disconnect
    if (disconnectDetected && (millis() - disconnectTime >= 500)) {
        disconnectDetected = false;
        BLEDevice::startAdvertising();
        Serial.println("[DIAGNOSTIC] BLE advertising restarted.");
    }

    // Diagnostics for link-layer connection states
    if (connected && !lastConnectedState) {
        lastConnectedState = connected;
        Serial.println("[DIAGNOSTIC] BLE link-layer connected.");
    }
    if (!connected && lastConnectedState) {
        lastConnectedState = connected;
        Serial.println("[DIAGNOSTIC] BLE link-layer disconnected.");
    }

    // Monitor subscription state changes
    static bool wasSubscribed = false;
    bool subscribed = isReadyToNotify();
    if (subscribed && !wasSubscribed) {
        wasSubscribed = true;
        Serial.println("[DIAGNOSTIC] BLE client subscribed to notifications.");
    } else if (!subscribed) {
        wasSubscribed = false;
    }

    // Retransmit first pending event in queue if ready to notify and connection has settled
    static unsigned long lastEventNotifyMillis = 0;
    if (isReadyToNotify() && (millis() - connectionTime >= 2000) && unsentCount > 0) {
        if (millis() - lastEventNotifyMillis >= 3000) {
            lastEventNotifyMillis = millis();
            Serial.println("[DIAGNOSTIC] Triggering retransmission of queued event.");
            notifyMedicationEventRecord(unsentEvents[0]);
        }
    }
}

void BLEManager::handleConnect() {
    connected = true;
    connectionTime = millis();
    Serial.println("[DIAGNOSTIC] handleConnect callback triggered.");
}

void BLEManager::handleDisconnect() {
    connected = false;
    disconnectDetected = true;
    disconnectTime = millis();
    Serial.println("[DIAGNOSTIC] handleDisconnect callback triggered.");
}

bool BLEManager::isReadyToNotify() const {
    return connected && pStatusConfigDescriptor != nullptr && pStatusConfigDescriptor->getNotifications();
}

void BLEManager::handleTimeSyncWrite(uint8_t* data, size_t length) {
    if (length < 13) {
        Serial.print("Error: TimeSync packet too short: ");
        Serial.println(length);
        return;
    }

    uint8_t packetType = data[0];
    if (packetType != 0x01) {
        Serial.print("Error: Invalid TimeSync packet type: ");
        Serial.println(packetType);
        return;
    }

    // Decode binary data (Little Endian for multi-byte values)
    uint32_t timestamp = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
    uint16_t year = data[5] | (data[6] << 8);
    uint8_t month = data[7];
    uint8_t day = data[8];
    uint8_t hour = data[9];
    uint8_t minute = data[10];
    uint8_t second = data[11];
    uint8_t weekday = data[12];

    // Store sync values
    syncTimestamp = timestamp;
    syncDay = day;
    syncMonth = month;
    syncYear = year;
    syncHour = hour;
    syncMinute = minute;
    syncSecond = second;
    syncWeekday = weekday;

    timeSyncPending = true;
    Serial.printf("Queued TimeSync: %04d-%02d-%02d %02d:%02d:%02d WD:%d TS:%u\n",
                  year, month, day, hour, minute, second, weekday, timestamp);
}

void BLEManager::handleStatusConfigWrite(uint8_t* data, size_t length) {
    if (length < 1) return;

    uint8_t packetType = data[0];

    // Handle event acknowledgement (0x06)
    if (packetType == 0x06) {
        if (length >= 5) {
            uint32_t ackId = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
            Serial.printf("Received BLE ACK for event ID: %u\n", ackId);
            if (unsentCount > 0 && unsentEvents[0].eventId == ackId) {
                for (uint8_t i = 1; i < unsentCount; i++) {
                    unsentEvents[i - 1] = unsentEvents[i];
                }
                unsentCount--;
                saveEvents();
                Serial.printf("Removed event from queue. Remaining: %d\n", unsentCount);
            }
        }
        return;
    }

    if (length < 6) {
        Serial.print("Error: MedConfig packet too short: ");
        Serial.println(length);
        return;
    }

    if (packetType != 0x02) {
        return;
    }

    uint8_t id = data[1];
    uint8_t hour = data[2];
    uint8_t minute = data[3];
    uint8_t dose = data[4];
    bool active = data[5] != 0;

    cfgId = id;
    cfgHour = hour;
    cfgMinute = minute;
    cfgDose = dose;
    cfgActive = active;

    medConfigPending = true;
    Serial.printf("Queued MedConfig ID:%d %02d:%02d x%d Act:%d\n", id, hour, minute, dose, active);
}

bool BLEManager::checkTimeSyncPending(uint32_t& timestamp, uint8_t& day, uint8_t& month, uint16_t& year,
                                     uint8_t& hour, uint8_t& minute, uint8_t& second,
                                     uint8_t& weekday) {
    if (timeSyncPending) {
        timestamp = syncTimestamp;
        day = syncDay;
        month = syncMonth;
        year = syncYear;
        hour = syncHour;
        minute = syncMinute;
        second = syncSecond;
        weekday = syncWeekday;
        
        timeSyncPending = false; // Reset volatile flag
        return true;
    }
    return false;
}

bool BLEManager::checkMedConfigPending(uint8_t& id, uint8_t& hour, uint8_t& minute,
                                      uint8_t& dose, bool& active) {
    if (medConfigPending) {
        id = cfgId;
        hour = cfgHour;
        minute = cfgMinute;
        dose = cfgDose;
        active = cfgActive;
        
        medConfigPending = false; // Reset volatile flag
        return true;
    }
    return false;
}

void BLEManager::notifyMedicationEvent(uint8_t statusCode) {
    if (!isReadyToNotify()) {
        Serial.printf("[DIAGNOSTIC] notifyMedicationEvent(0x%02X) skipped - client not subscribed.\n", statusCode);
        return;
    }

    // Send a 2-byte packet back: [0x04, statusCode]
    uint8_t response[2] = { 0x04, statusCode };
    pStatusConfigChar->setValue(response, 2);
    pStatusConfigChar->notify();
    Serial.printf("[DIAGNOSTIC] BLE notified medication event: 0x%02X\n", statusCode);
}

void BLEManager::notifyMedicationConfig(uint8_t id, uint8_t hour, uint8_t minute, uint8_t dose, bool active) {
    // Send a 6-byte packet: [0x02, id, hour, minute, dose, active]
    uint8_t packet[6] = { 0x02, id, hour, minute, dose, active ? (uint8_t)1 : (uint8_t)0 };
    pStatusConfigChar->setValue(packet, 6);
    if (isReadyToNotify()) {
        pStatusConfigChar->notify();
        Serial.printf("[DIAGNOSTIC] BLE notified schedule config: ID:%d %02d:%02d x%d Act:%d\n", id, hour, minute, dose, active);
    } else {
        Serial.println("[DIAGNOSTIC] notifyMedicationConfig skipped - client not subscribed.");
    }
}

void BLEManager::notifyMedicationEventRecord(const MedicationEvent& event) {
    if (!isReadyToNotify()) {
        Serial.printf("[DIAGNOSTIC] notifyMedicationEventRecord(ID:%u) skipped - client not subscribed.\n", event.eventId);
        return;
    }

    // Send a 14-byte packet:
    // [0x04, 0x03, eventId_0..3, scheduleId, yearOffset, month, day, hour, minute, dose, source]
    uint8_t packet[14];
    packet[0] = 0x04;
    packet[1] = 0x03; // TAKEN
    packet[2] = event.eventId & 0xFF;
    packet[3] = (event.eventId >> 8) & 0xFF;
    packet[4] = (event.eventId >> 16) & 0xFF;
    packet[5] = (event.eventId >> 24) & 0xFF;
    packet[6] = event.scheduleId;
    packet[7] = event.scheduledYearOffset;
    packet[8] = event.scheduledMonth;
    packet[9] = event.scheduledDay;
    packet[10] = event.scheduledHour;
    packet[11] = event.scheduledMinute;
    packet[12] = event.dose;
    packet[13] = event.source;

    pStatusConfigChar->setValue(packet, 14);
    pStatusConfigChar->notify();
    Serial.printf("[DIAGNOSTIC] BLE notified event ID:%u schedule:%d\n", event.eventId, event.scheduleId);
}

void BLEManager::addMedicationEvent(uint8_t scheduleId, uint8_t scheduledHour, uint8_t scheduledMinute,
                                    uint8_t dose, uint8_t source, uint8_t yearOffset,
                                    uint8_t month, uint8_t day, uint32_t epoch) {
    if (unsentCount >= MAX_UNSENT_EVENTS) {
        // Queue full, discard oldest event by shifting left
        for (uint8_t i = 1; i < MAX_UNSENT_EVENTS; i++) {
            unsentEvents[i - 1] = unsentEvents[i];
        }
        unsentCount = MAX_UNSENT_EVENTS - 1;
    }

    unsentEvents[unsentCount] = {
        epoch,
        scheduleId,
        scheduledHour,
        scheduledMinute,
        dose,
        0x03, // TAKEN
        source,
        yearOffset,
        month,
        day
    };
    unsentCount++;
    saveEvents();

    Serial.printf("Queued medication taken event ID: %u. Queue count: %d\n", epoch, unsentCount);

    // If already connected and client has subscribed, trigger notification immediately
    if (isReadyToNotify()) {
        notifyMedicationEventRecord(unsentEvents[0]);
    }
}

void BLEManager::saveEvents() {
    preferences.begin("medremind", false);
    preferences.putBytes("events", unsentEvents, unsentCount * sizeof(MedicationEvent));
    preferences.putUChar("count", unsentCount);
    preferences.end();
    Serial.println("Saved unsent medication events to storage.");
}

void BLEManager::loadEvents() {
    preferences.begin("medremind", true);
    unsentCount = preferences.getUChar("count", 0);
    if (unsentCount > MAX_UNSENT_EVENTS) {
        unsentCount = 0;
    }
    if (unsentCount > 0) {
        preferences.getBytes("events", unsentEvents, unsentCount * sizeof(MedicationEvent));
        Serial.printf("Loaded %d unsent medication events from storage.\n", unsentCount);
    } else {
        Serial.println("No pending unsent medication events in storage.");
    }
    preferences.end();
}
