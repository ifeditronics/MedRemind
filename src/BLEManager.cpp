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
      connected(false), lastConnectedState(false), timeSyncPending(false),
      syncDay(0), syncMonth(0), syncYear(0), syncHour(0), syncMinute(0),
      syncSecond(0), syncWeekday(0), medConfigPending(false),
      cfgId(0), cfgHour(0), cfgMinute(0), cfgDose(0), cfgActive(false) {}

void BLEManager::init() {
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
    pStatusConfigChar->addDescriptor(new BLE2902());

    // 6. Start Service
    pService->start();

    // 7. Start Advertising
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("BLE Server started and advertising...");
}

void BLEManager::update() {
    // Check if device disconnected and restart advertising
    if (!connected && lastConnectedState) {
        delay(500); // Wait for BLE stack to stabilize
        pServer->startAdvertising();
        Serial.println("BLE client disconnected. Restarted advertising.");
        lastConnectedState = connected;
    }
    if (connected && !lastConnectedState) {
        lastConnectedState = connected;
        Serial.println("BLE client connected.");
    }
}

void BLEManager::handleConnect() {
    connected = true;
}

void BLEManager::handleDisconnect() {
    connected = false;
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
    if (length < 6) {
        Serial.print("Error: MedConfig packet too short: ");
        Serial.println(length);
        return;
    }

    uint8_t packetType = data[0];
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

bool BLEManager::checkTimeSyncPending(uint8_t& day, uint8_t& month, uint16_t& year,
                                     uint8_t& hour, uint8_t& minute, uint8_t& second,
                                     uint8_t& weekday) {
    if (timeSyncPending) {
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
    if (!connected) return;

    // Send a 2-byte packet back: [0x04, statusCode]
    uint8_t response[2] = { 0x04, statusCode };
    pStatusConfigChar->setValue(response, 2);
    pStatusConfigChar->notify();
    Serial.printf("BLE notified medication event: 0x%02X\n", statusCode);
}
