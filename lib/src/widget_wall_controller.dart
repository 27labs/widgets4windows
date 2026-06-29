import 'dart:async';
import 'dart:io';

import 'package:widget_wall/src/config.dart';
import 'package:widget_wall/src/windows_api.dart';
import 'package:widget_wall/src/windows_event_log.dart';

const Duration _startupDelay = Duration(milliseconds: 2700);
const Duration _windowEnforcementInterval = Duration(milliseconds: 2700);
const Duration _processTerminationTimeout = Duration(milliseconds: 2700 + 2700);
const Duration _windowOperationInitialRetryDelay = Duration(milliseconds: 100);

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

    await Future.wait(
      config.widgets.map((widget) => _startWidget(widget, layout)),
    );

    _enforcerTimer = Timer.periodic(_windowEnforcementInterval, (_) {
      for (final entry in _managed) {
        if (isWindowAlive(entry.hwnd)) {
          _enforceWindow(entry);
        }
      }
    });
  }

  Future<void> _startWidget(WidgetEntry widget, GridLayout layout) async {
    final process = await Process.start(
      widget.exe,
      widget.arguments,
      workingDirectory: widget.workingDirectory,
    );
    _drainProcessOutput(process);

    final assignedToJob = await _assignProcessToJob(process);
    if (!assignedToJob) return;

    final hwnd = await waitForMainWindow(
      pid: process.pid,
      timeout: widget.windowPollTimeout,
    );

    if (hwnd == null) {
      eventLog.warning(
        'Killing PID ${process.pid} (${widget.exe}) because no visible top-level window appeared.',
      );
      process.kill();
      return;
    }

    final rect = layout.rectFor(
      row: widget.row,
      column: widget.column,
      rowSpan: widget.rowSpan,
      columnSpan: widget.columnSpan,
    );

    final managed = ManagedWidgetProcess(
      process: process,
      hwnd: hwnd,
      rect: rect,
    );
    _managed.add(managed);
    _enforceWindow(managed, includePushToBottom: false);
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
      try {
        closeWindowGracefully(hwnd);
      } catch (error) {
        eventLog.error(
          'event=window.close.failed hwnd=$hwnd',
          error,
        );
      }
    }
    _managed.clear();
  }

  void _enforceWindow(
    ManagedWidgetProcess entry, {
    bool includePushToBottom = true,
  }) {
    final hwnd = entry.hwnd;

    _startWindowOperationRetries(
      operation: 'hide-taskbar',
      hwnd: hwnd,
      action: () => hideWindowFromTaskbar(hwnd),
    );
    _startWindowOperationRetries(
      operation: 'place-window',
      hwnd: hwnd,
      action: () => showAndPlaceWindow(hwnd, entry.rect),
    );
    if (includePushToBottom) {
      _startWindowOperationRetries(
        operation: 'push-to-bottom',
        hwnd: hwnd,
        action: () => pushWindowToBottom(hwnd),
      );
    }
  }

  void _startWindowOperationRetries({
    required String operation,
    required int hwnd,
    required void Function() action,
  }) {
    unawaited(
      _retryWindowOperation(
        operation: operation,
        hwnd: hwnd,
        action: action,
      ),
    );
  }

  Future<void> _retryWindowOperation({
    required String operation,
    required int hwnd,
    required void Function() action,
  }) async {
    var attempt = 1;
    var retryDelay = _windowOperationInitialRetryDelay;
    final elapsed = Stopwatch()..start();

    while (!_disposed && isWindowAlive(hwnd)) {
      try {
        action();
        return;
      } catch (error) {
        final remaining = _windowEnforcementInterval - elapsed.elapsed;
        final willRetry = retryDelay < remaining;
        eventLog.error(
          'event=window.operation.failed operation=$operation hwnd=$hwnd '
          'attempt=$attempt retryInMs='
          '${willRetry ? retryDelay.inMilliseconds : 'none'}',
          error,
        );

        if (!willRetry) return;
        await Future<void>.delayed(retryDelay);
        retryDelay = Duration(
          microseconds: retryDelay.inMicroseconds * 2,
        );
        attempt++;
      }
    }
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
