import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int jobObjectLimitKillOnJobClose = 0x00002000;
const int spiGetWorkArea = 0x0030;
const int dwmwaExtendedFrameBounds = 9;
const Duration _windowPollInterval = Duration(milliseconds: 270);

class DisplayBounds {
  const DisplayBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

class GridRect {
  const GridRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

class WindowInsets {
  const WindowInsets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
}

final class WindowOperationException implements Exception {
  const WindowOperationException({
    required this.operation,
    required this.hwnd,
    required this.win32Error,
  });

  final String operation;
  final int hwnd;
  final int win32Error;

  @override
  String toString() {
    return '$operation failed for HWND $hwnd '
        '(Win32 error $win32Error).';
  }
}

class GridLayout {
  GridLayout({
    required this.rows,
    required this.columns,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.padding,
  }) {
    if (width < columns || height < rows) {
      throw FormatException(
        'The ${width}x$height primary work area cannot provide at least one '
        'pixel per cell for grid.rows=$rows and grid.columns=$columns.',
      );
    }

    final maxHorizontalPadding = (width - columns) ~/ (columns + 1);
    final maxVerticalPadding = (height - rows) ~/ (rows + 1);
    final maxPadding = maxHorizontalPadding < maxVerticalPadding
        ? maxHorizontalPadding
        : maxVerticalPadding;
    if (padding > maxPadding) {
      throw FormatException(
        'grid.padding is $padding, but its maximum is $maxPadding for a '
        '${rows}x$columns grid in the ${width}x$height primary work area.',
      );
    }
  }

  final int rows;
  final int columns;
  final int left;
  final int top;
  final int width;
  final int height;
  final int padding;

  GridRect rectFor({
    required int row,
    required int column,
    required int rowSpan,
    required int columnSpan,
  }) {
    final trackWidth =
        (width - (padding * 2) - (padding * (columns - 1))).clamp(0, width);
    final trackHeight =
        (height - (padding * 2) - (padding * (rows - 1))).clamp(0, height);
    final rectLeft = left +
        padding +
        ((column * trackWidth) ~/ columns) +
        (column * padding);
    final rectTop =
        top + padding + ((row * trackHeight) ~/ rows) + (row * padding);
    final rectRight = left +
        padding +
        (((column + columnSpan) * trackWidth) ~/ columns) +
        ((column + columnSpan - 1) * padding);
    final rectBottom = top +
        padding +
        (((row + rowSpan) * trackHeight) ~/ rows) +
        ((row + rowSpan - 1) * padding);

    return GridRect(
      left: rectLeft,
      top: rectTop,
      width: rectRight - rectLeft,
      height: rectBottom - rectTop,
    );
  }
}

DisplayBounds getPrimaryWorkAreaBounds() {
  final rect = calloc<RECT>();
  try {
    final result = SystemParametersInfo(
      spiGetWorkArea,
      0,
      rect,
      SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
    );
    if (result == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }

    return DisplayBounds(
      left: rect.ref.left,
      top: rect.ref.top,
      width: rect.ref.right - rect.ref.left,
      height: rect.ref.bottom - rect.ref.top,
    );
  } finally {
    calloc.free(rect);
  }
}

void showAndPlaceWindow(int hwnd, GridRect rect) {
  ShowWindow(hwnd, SW_RESTORE);
  final insets = getWindowVisibleInsets(hwnd);
  final result = SetWindowPos(
    hwnd,
    HWND_BOTTOM,
    rect.left - insets.left,
    rect.top - insets.top,
    rect.width + insets.left + insets.right,
    rect.height + insets.top + insets.bottom,
    SWP_NOACTIVATE | SWP_SHOWWINDOW,
  );
  _checkWindowOperation(result, 'SetWindowPos(place)', hwnd);
}

void hideWindowFromTaskbar(int hwnd) {
  SetLastError(0);
  final extendedStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  final getStyleError = GetLastError();
  if (extendedStyle == 0 && getStyleError != 0) {
    throw WindowOperationException(
      operation: 'GetWindowLongPtr(GWL_EXSTYLE)',
      hwnd: hwnd,
      win32Error: getStyleError,
    );
  }

  final hiddenStyle = (extendedStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
  if (hiddenStyle != extendedStyle) {
    SetLastError(0);
    final previousStyle = SetWindowLongPtr(hwnd, GWL_EXSTYLE, hiddenStyle);
    final setStyleError = GetLastError();
    if (previousStyle == 0 && setStyleError != 0) {
      throw WindowOperationException(
        operation: 'SetWindowLongPtr(GWL_EXSTYLE)',
        hwnd: hwnd,
        win32Error: setStyleError,
      );
    }
  }

  final result = SetWindowPos(
    hwnd,
    0,
    0,
    0,
    0,
    0,
    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
  );
  _checkWindowOperation(result, 'SetWindowPos(frame)', hwnd);
}

void pushWindowToBottom(int hwnd) {
  final result = SetWindowPos(
    hwnd,
    HWND_BOTTOM,
    0,
    0,
    0,
    0,
    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
  );
  _checkWindowOperation(result, 'SetWindowPos(z-order)', hwnd);
}

bool isWindowAlive(int hwnd) => IsWindow(hwnd) != 0;

void closeWindowGracefully(int hwnd) {
  final result = PostMessage(hwnd, WM_CLOSE, 0, 0);
  _checkWindowOperation(result, 'PostMessage(WM_CLOSE)', hwnd);
}

void _checkWindowOperation(int result, String operation, int hwnd) {
  if (result != 0) return;
  throw WindowOperationException(
    operation: operation,
    hwnd: hwnd,
    win32Error: GetLastError(),
  );
}

WindowInsets getWindowVisibleInsets(int hwnd) {
  final outerRect = calloc<RECT>();
  final visibleRect = calloc<RECT>();
  try {
    final hasOuter = GetWindowRect(hwnd, outerRect) != 0;
    final hasVisible = DwmGetWindowAttribute(
          hwnd,
          dwmwaExtendedFrameBounds,
          visibleRect,
          sizeOf<RECT>(),
        ) ==
        S_OK;

    if (!hasOuter || !hasVisible) {
      return const WindowInsets(left: 0, top: 0, right: 0, bottom: 0);
    }

    return WindowInsets(
      left: visibleRect.ref.left - outerRect.ref.left,
      top: visibleRect.ref.top - outerRect.ref.top,
      right: outerRect.ref.right - visibleRect.ref.right,
      bottom: outerRect.ref.bottom - visibleRect.ref.bottom,
    );
  } finally {
    calloc.free(outerRect);
    calloc.free(visibleRect);
  }
}

final class WindowsJobObject {
  WindowsJobObject._(this._handle);

  final int _handle;

  static WindowsJobObject createKillOnClose() {
    final name = nullptr;
    final handle = CreateJobObject(nullptr, name);
    if (handle == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }

    final info = calloc<JobObjectExtendedLimitInformationStruct>();
    try {
      info.ref.basicLimitInformation.limitFlags = jobObjectLimitKillOnJobClose;
      final success = SetInformationJobObject(
        handle,
        JobObjectExtendedLimitInformation,
        info.cast(),
        sizeOf<JobObjectExtendedLimitInformationStruct>(),
      );
      if (success == 0) {
        CloseHandle(handle);
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
      return WindowsJobObject._(handle);
    } finally {
      calloc.free(info);
    }
  }

  void assignProcess(int pid) {
    final access = PROCESS_SET_QUOTA | PROCESS_TERMINATE;
    final processHandle = OpenProcess(access, FALSE, pid);
    if (processHandle == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }

    try {
      final success = AssignProcessToJobObject(_handle, processHandle);
      if (success == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
    } finally {
      CloseHandle(processHandle);
    }
  }

  void close() {
    CloseHandle(_handle);
  }
}

int? _findMainWindow(int pid) {
  int? foundHwnd;
  final pidPointer = calloc<Uint32>();
  final callback = NativeCallable<WNDENUMPROC>.isolateLocal(
    (int hwnd, int _) {
      pidPointer.value = 0;
      GetWindowThreadProcessId(hwnd, pidPointer);
      final isVisible = IsWindowVisible(hwnd) != 0;
      final owner = GetWindow(hwnd, GW_OWNER);
      if (isVisible && owner == 0 && pidPointer.value == pid) {
        foundHwnd = hwnd;
        return FALSE;
      }
      return TRUE;
    },
    exceptionalReturn: TRUE,
  );

  try {
    EnumWindows(callback.nativeFunction, 0);
    return foundHwnd;
  } finally {
    callback.close();
    calloc.free(pidPointer);
  }
}

Future<int?> waitForMainWindow({
  required int pid,
  required Duration timeout,
}) async {
  final elapsed = Stopwatch()..start();

  while (elapsed.elapsed < timeout) {
    final hwnd = _findMainWindow(pid);
    if (hwnd != null) return hwnd;

    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) break;
    await Future<void>.delayed(
      remaining < _windowPollInterval ? remaining : _windowPollInterval,
    );
  }

  return null;
}

base class JobObjectBasicLimitInformation extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;

  @Int64()
  external int perJobUserTimeLimit;

  @Uint32()
  external int limitFlags;

  @IntPtr()
  external int minimumWorkingSetSize;

  @IntPtr()
  external int maximumWorkingSetSize;

  @Uint32()
  external int activeProcessLimit;

  @IntPtr()
  external int affinity;

  @Uint32()
  external int priorityClass;

  @Uint32()
  external int schedulingClass;
}

base class IoCounters extends Struct {
  @Uint64()
  external int readOperationCount;

  @Uint64()
  external int writeOperationCount;

  @Uint64()
  external int otherOperationCount;

  @Uint64()
  external int readTransferCount;

  @Uint64()
  external int writeTransferCount;

  @Uint64()
  external int otherTransferCount;
}

base class JobObjectExtendedLimitInformationStruct extends Struct {
  external JobObjectBasicLimitInformation basicLimitInformation;

  external IoCounters ioInfo;

  @IntPtr()
  external int processMemoryLimit;

  @IntPtr()
  external int jobMemoryLimit;

  @IntPtr()
  external int peakProcessMemoryUsed;

  @IntPtr()
  external int peakJobMemoryUsed;
}
