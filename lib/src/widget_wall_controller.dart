import 'dart:async';
import 'dart:io';

import 'package:widget_wall/src/config.dart';
import 'package:widget_wall/src/windows_api.dart';

class WidgetWallController {
  WidgetWallController({required this.config});

  final WallConfig config;

  final List<ManagedWidgetProcess> _managed = [];
  Timer? _enforcerTimer;
  WindowsJobObject? _jobObject;
  bool _disposed = false;

  Future<void> start() async {
    if (_jobObject != null) {
      throw StateError('WidgetWallController.start() was already called.');
    }

    _jobObject = WindowsJobObject.createKillOnClose();
    final display = getPrimaryWorkAreaBounds();
    final layout = GridLayout(
      rows: config.rows,
      columns: config.columns,
      left: display.left,
      top: display.top,
      width: display.width,
      height: display.height,
      padding: config.padding,
    );

    for (final widget in config.widgets) {
      final existingWindows =
          listVisibleTopLevelWindows().map((window) => window.hwnd).toSet();

      final process = await Process.start(
        widget.exe,
        widget.arguments,
        workingDirectory: widget.workingDirectory,
      );

      _tryAssignProcessToJob(process.pid);

      final hwnd = await waitForNewTopLevelWindow(
            existingHandles: existingWindows,
            timeout: widget.windowPollTimeout,
          ) ??
          await waitForMainWindow(
            pid: process.pid,
            timeout: widget.windowPollTimeout,
          );

      if (hwnd == null) {
        stderr.writeln(
          'Skipping layout for PID ${process.pid} (${widget.exe}) because no visible top-level window appeared.',
        );
        _managed.add(
          ManagedWidgetProcess(process: process, hwnd: null, rect: null),
        );
        continue;
      }

      final ownerPid = getWindowProcessId(hwnd);
      if (ownerPid != process.pid) {
        _tryAssignProcessToJob(ownerPid);
      }

      final rect = layout.rectFor(
        row: widget.row,
        column: widget.column,
        rowSpan: widget.rowSpan,
        columnSpan: widget.columnSpan,
      );

      showAndPlaceWindow(hwnd, rect);
      _managed
          .add(ManagedWidgetProcess(process: process, hwnd: hwnd, rect: rect));
    }

    _enforcerTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      for (final entry in _managed) {
        final hwnd = entry.hwnd;
        final rect = entry.rect;
        if (hwnd != null && rect != null && isWindowAlive(hwnd)) {
          showAndPlaceWindow(hwnd, rect);
          pushWindowToBottom(hwnd);
        }
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _enforcerTimer?.cancel();
    _enforcerTimer = null;

    _jobObject?.close();
    _jobObject = null;

    for (final entry in _managed) {
      entry.process.kill();
    }
    _managed.clear();
  }

  void _tryAssignProcessToJob(int pid) {
    try {
      _jobObject?.assignProcess(pid);
    } catch (_) {
      stderr.writeln('Warning: could not assign PID $pid to the cleanup job.');
    }
  }
}

class ManagedWidgetProcess {
  ManagedWidgetProcess({
    required this.process,
    required this.hwnd,
    required this.rect,
  });

  final Process process;
  final int? hwnd;
  final GridRect? rect;
}
