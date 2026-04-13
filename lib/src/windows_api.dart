import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int jobObjectLimitKillOnJobClose = 0x00002000;
const int spiGetWorkArea = 0x0030;
const int dwmwaExtendedFrameBounds = 9;

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

class WindowInfo {
  const WindowInfo({
    required this.hwnd,
    required this.pid,
  });

  final int hwnd;
  final int pid;
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
  });

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
  SetWindowPos(
    hwnd,
    HWND_BOTTOM,
    rect.left - insets.left,
    rect.top - insets.top,
    rect.width + insets.left + insets.right,
    rect.height + insets.top + insets.bottom,
    SWP_NOACTIVATE | SWP_SHOWWINDOW,
  );
}

void hideWindowFromTaskbar(int hwnd) {
  final extendedStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  final hiddenStyle = (extendedStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
  if (hiddenStyle != extendedStyle) {
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, hiddenStyle);
  }

  SetWindowPos(
    hwnd,
    0,
    0,
    0,
    0,
    0,
    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
  );
}

void pushWindowToBottom(int hwnd) {
  SetWindowPos(
    hwnd,
    HWND_BOTTOM,
    0,
    0,
    0,
    0,
    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
  );
}

bool isWindowAlive(int hwnd) => IsWindow(hwnd) != 0;

void closeWindowGracefully(int hwnd) {
  PostMessage(hwnd, WM_CLOSE, 0, 0);
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

class _WindowSearchState {
  _WindowSearchState({
    this.pid,
    this.existingHandles = const <int>{},
    this.searchForNewHandle = false,
  });

  final int? pid;
  final Set<int> existingHandles;
  final bool searchForNewHandle;
  int? hwnd;
  final List<WindowInfo> windows = [];
}

_WindowSearchState? _activeWindowSearch;

int _enumWindowsProc(int hwnd, int _) {
  final state = _activeWindowSearch;
  if (state == null) return TRUE;

  final pidPointer = calloc<Uint32>();
  try {
    GetWindowThreadProcessId(hwnd, pidPointer);
    final isVisible = IsWindowVisible(hwnd) != 0;
    final owner = GetWindow(hwnd, GW_OWNER);
    if (isVisible && owner == 0) {
      final windowInfo = WindowInfo(hwnd: hwnd, pid: pidPointer.value);
      state.windows.add(windowInfo);

      final matchesPid = state.pid != null && pidPointer.value == state.pid;
      final isNewHandle =
          state.searchForNewHandle && !state.existingHandles.contains(hwnd);
      if (matchesPid || isNewHandle) {
        state.hwnd = hwnd;
        return FALSE;
      }
    }
    return TRUE;
  } finally {
    calloc.free(pidPointer);
  }
}

List<WindowInfo> listVisibleTopLevelWindows() {
  final callback = Pointer.fromFunction<WNDENUMPROC>(_enumWindowsProc, TRUE);
  final state = _WindowSearchState();
  _activeWindowSearch = state;
  EnumWindows(callback, 0);
  _activeWindowSearch = null;
  return state.windows;
}

int getWindowProcessId(int hwnd) {
  final pidPointer = calloc<Uint32>();
  try {
    GetWindowThreadProcessId(hwnd, pidPointer);
    return pidPointer.value;
  } finally {
    calloc.free(pidPointer);
  }
}

Future<int?> waitForMainWindow({
  required int pid,
  required Duration timeout,
}) async {
  final startedAt = DateTime.now();
  final callback = Pointer.fromFunction<WNDENUMPROC>(_enumWindowsProc, TRUE);

  while (DateTime.now().difference(startedAt) < timeout) {
    final state = _WindowSearchState(pid: pid);
    _activeWindowSearch = state;
    EnumWindows(callback, 0);
    _activeWindowSearch = null;

    if (state.hwnd != null) {
      return state.hwnd;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  return null;
}

Future<int?> waitForNewTopLevelWindow({
  required Set<int> existingHandles,
  required Duration timeout,
}) async {
  final startedAt = DateTime.now();
  final callback = Pointer.fromFunction<WNDENUMPROC>(_enumWindowsProc, TRUE);

  while (DateTime.now().difference(startedAt) < timeout) {
    final state = _WindowSearchState(
      existingHandles: existingHandles,
      searchForNewHandle: true,
    );
    _activeWindowSearch = state;
    EnumWindows(callback, 0);
    _activeWindowSearch = null;

    if (state.hwnd != null) {
      return state.hwnd;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
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
