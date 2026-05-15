import 'dart:ffi';

import 'package:ffi/ffi.dart';

const int _eventlogErrorType = 0x0001;
const int _eventlogWarningType = 0x0002;
const int _eventlogInformationType = 0x0004;

const int _widgetWallErrorEventId = 1000;
const int _widgetWallWarningEventId = 1001;
const int _widgetWallInfoEventId = 1002;

final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');

typedef _RegisterEventSourceNative = IntPtr Function(
  Pointer<Utf16> serverName,
  Pointer<Utf16> sourceName,
);
typedef _RegisterEventSourceDart = int Function(
  Pointer<Utf16> serverName,
  Pointer<Utf16> sourceName,
);

typedef _ReportEventNative = Int32 Function(
  IntPtr eventLog,
  Uint16 type,
  Uint16 category,
  Uint32 eventId,
  Pointer<Void> userSid,
  Uint16 numberOfStrings,
  Uint32 dataSize,
  Pointer<Pointer<Utf16>> strings,
  Pointer<Void> rawData,
);
typedef _ReportEventDart = int Function(
  int eventLog,
  int type,
  int category,
  int eventId,
  Pointer<Void> userSid,
  int numberOfStrings,
  int dataSize,
  Pointer<Pointer<Utf16>> strings,
  Pointer<Void> rawData,
);

typedef _DeregisterEventSourceNative = Int32 Function(IntPtr eventLog);
typedef _DeregisterEventSourceDart = int Function(int eventLog);

final _RegisterEventSourceDart _registerEventSource = _advapi32
    .lookupFunction<_RegisterEventSourceNative, _RegisterEventSourceDart>(
  'RegisterEventSourceW',
);

final _ReportEventDart _reportEvent =
    _advapi32.lookupFunction<_ReportEventNative, _ReportEventDart>(
  'ReportEventW',
);

final _DeregisterEventSourceDart _deregisterEventSource = _advapi32
    .lookupFunction<_DeregisterEventSourceNative, _DeregisterEventSourceDart>(
  'DeregisterEventSource',
);

class WindowsEventLog {
  WindowsEventLog({String sourceName = 'Widget Wall'})
      : _sourceName = sourceName;

  final String _sourceName;

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.writeln();
      buffer.write(error);
    }
    if (stackTrace != null) {
      buffer.writeln();
      buffer.write(stackTrace);
    }
    _write(_eventlogErrorType, _widgetWallErrorEventId, buffer.toString());
  }

  void warning(String message) {
    _write(_eventlogWarningType, _widgetWallWarningEventId, message);
  }

  void info(String message) {
    _write(_eventlogInformationType, _widgetWallInfoEventId, message);
  }

  void _write(int type, int eventId, String message) {
    final sourceName = _sourceName.toNativeUtf16();
    final eventMessage = message.toNativeUtf16();
    final strings = calloc<Pointer<Utf16>>();

    try {
      strings[0] = eventMessage;
      final eventLog = _registerEventSource(nullptr, sourceName);
      if (eventLog == 0) return;

      try {
        _reportEvent(
          eventLog,
          type,
          0,
          eventId,
          nullptr,
          1,
          0,
          strings,
          nullptr,
        );
      } finally {
        _deregisterEventSource(eventLog);
      }
    } finally {
      calloc.free(strings);
      calloc.free(eventMessage);
      calloc.free(sourceName);
    }
  }
}
