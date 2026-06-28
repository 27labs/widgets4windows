import 'dart:async';
import 'dart:io';

import 'package:widget_wall/src/config.dart';
import 'package:widget_wall/src/windows_api.dart';
import 'package:widget_wall/src/windows_event_log.dart';

const Duration _startupDelay = Duration(milliseconds: 2700);
const Duration _windowEnforcementInterval = Duration(milliseconds: 2700);
const Duration _processTerminationTimeout = Duration(milliseconds: 2700+2700);

class WidgetWallController {
  WidgetWallController({
    required this.config,
    required this.eventLog,
  });

  final WallConfig config;
  final WindowsEventLog eventLog;

  final List<ManagedWidgetProcess> _managed = [];
  Timer? _enforcerTimer;
  WindowsJobObject? _jobObject;
  bool _disposed = false;

  Future<void> start() async {
    if (_jobObject != null) {
      throw StateError('WidgetWallController.start() was already called.');
    }

    await Future<void>.delayed(_startupDelay);

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
      final process = await Process.start(
        widget.exe,
        widget.arguments,
        workingDirectory: widget.workingDirectory,
      );
      _drainProcessOutput(process);

      final assignedToJob = await _assignProcessToJob(process);
      if (!assignedToJob) {
        continue;
      }

      final hwnd = await waitForMainWindow(
        pid: process.pid,
        timeout: widget.windowPollTimeout,
      );

      if (hwnd == null) {
        eventLog.warning(
          'Killing PID ${process.pid} (${widget.exe}) because no visible top-level window appeared.',
        );
        process.kill();
        continue;
      }

      final rect = layout.rectFor(
        row: widget.row,
        column: widget.column,
        rowSpan: widget.rowSpan,
        columnSpan: widget.columnSpan,
      );

      hideWindowFromTaskbar(hwnd);
      showAndPlaceWindow(hwnd, rect);
      _managed.add(
        ManagedWidgetProcess(
          process: process,
          hwnd: hwnd,
          rect: rect,
        ),
      );
    }

    _enforcerTimer = Timer.periodic(_windowEnforcementInterval, (_) {
      for (final entry in _managed) {
        final hwnd = entry.hwnd;
        final rect = entry.rect;
        if (isWindowAlive(hwnd)) {
          hideWindowFromTaskbar(hwnd);
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
      final hwnd = entry.hwnd;
      closeWindowGracefully(hwnd);
    }
    _managed.clear();
  }

  Future<bool> _assignProcessToJob(Process process) async {
    try {
      _jobObject!.assignProcess(process.pid);
      return true;
    } catch (error, stackTrace) {
      eventLog.error(
        'Could not assign PID ${process.pid} to the cleanup job. '
        'Terminating it immediately.',
        error,
        stackTrace,
      );

      process.kill();
      try {
        await process.exitCode.timeout(_processTerminationTimeout);
      } on TimeoutException catch (terminationError, terminationStackTrace) {
        eventLog.error(
          'PID ${process.pid} did not exit within '
          '${_processTerminationTimeout.inSeconds} seconds.',
          terminationError,
          terminationStackTrace,
        );
        rethrow;
      }

      return false;
    }
  }

  void _drainProcessOutput(Process process) {
    process.stdout.drain<void>();
    process.stderr.listen((data) {
      final message = systemEncoding.decode(data).trim();
      if (message.isNotEmpty) {
        eventLog.warning(
          'Widget process ${process.pid} wrote to stderr: $message',
        );
      }
    });
  }
}

class ManagedWidgetProcess {
  ManagedWidgetProcess({
    required this.process,
    required this.hwnd,
    required this.rect,
  });

  final Process process;
  final int hwnd;
  final GridRect rect;
}
