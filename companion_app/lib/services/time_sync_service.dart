import 'dart:typed_data';

class TimeSyncService {
  /// Builds a 13-byte time sync packet:
  /// - Byte 0: 0x01 (packet type)
  /// - Bytes 1-4: unix epoch timestamp (little-endian uint32)
  /// - Bytes 5-6: year (little-endian uint16)
  /// - Byte 7: month (1-12)
  /// - Byte 8: day (1-31)
  /// - Byte 9: hour (0-23)
  /// - Byte 10: minute (0-59)
  /// - Byte 11: second (0-59)
  /// - Byte 12: weekday (0-6, where 0=Sunday, 1=Monday, ..., 6=Saturday)
  static List<int> createSyncPacket() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch ~/ 1000; // Epoch in seconds
    
    // Map Dart weekday (1=Monday, ..., 7=Sunday) to ESP32 weekday (0=Sunday, 1=Monday, ..., 6=Saturday)
    final espWeekday = (now.weekday == DateTime.sunday) ? 0 : now.weekday;

    final bytes = ByteData(13);
    
    bytes.setUint8(0, 0x01); // packet type
    
    // Unix timestamp (little endian uint32)
    bytes.setUint32(1, timestamp, Endian.little);
    
    // Year (little endian uint16)
    bytes.setUint16(5, now.year, Endian.little);
    
    bytes.setUint8(7, now.month);
    bytes.setUint8(8, now.day);
    bytes.setUint8(9, now.hour);
    bytes.setUint8(10, now.minute);
    bytes.setUint8(11, now.second);
    bytes.setUint8(12, espWeekday);
    
    return bytes.buffer.asUint8List();
  }
}
