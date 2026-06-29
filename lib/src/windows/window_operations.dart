import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'grid_layout.dart';

const int spiGetWorkArea = 0x0030;
const int dwmwaExtendedFrameBounds = 9;
const Duration _windowPollInterval = Duration(milliseconds: 270);

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
