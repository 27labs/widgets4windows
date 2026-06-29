import 'dart:async';
import 'dart:io';

import 'package:widget_wall/src/config.dart';
import 'package:widget_wall/src/widget_wall_controller.dart';
import 'package:widget_wall/src/windows_event_log.dart';
import 'package:win32/win32.dart';

Future<void> main(List<String> args) async {
  // Keep work-area and window-placement coordinates in physical pixels.
  // This must happen before this process makes any window-system calls.
  registerHighDPISupport();

  final eventLog = WindowsEventLog();

  final configPath = args.isNotEmpty ? args.first : _defaultConfigPath();
  final WallConfig config;
  try {
    config = await WallConfig.load(configPath);
  } on PathNotFoundException catch (error) {
    eventLog.error(
      'Configuration file not found: "$configPath".',
      error,
    );
    exitCode = 1;
    return;
  } on FormatException catch (error) {
    eventLog.error(
      'Invalid configuration file "$configPath".',
      error,
    );
    exitCode = 1;
    return;
  } on FileSystemException catch (error) {
    eventLog.error(
      'Could not read configuration file "$configPath".',
      error,
    );
    exitCode = 1;
    return;
  }

  WidgetWallController? controller;
  try {
    controller = WidgetWallController(config: config, eventLog: eventLog);

    Future<void> shutdown() async {
      eventLog.info('Shutting down widget wall.');
      await controller?.dispose();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown()));

    await controller.start();
    eventLog.info(
      'Widget Wall is running with ${config.widgets.length} configured app(s).',
    );

    final done = Completer<void>();
    await done.future;
  } on FormatException catch (error) {
    eventLog.error(
      'Invalid configuration file "$configPath".',
      error,
    );
    exitCode = 1;
    await controller?.dispose();
  } catch (error, stackTrace) {
    eventLog.error('Widget Wall failed.', error, stackTrace);
    exitCode = 1;
    await controller?.dispose();
  }
}

String _defaultConfigPath() {
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  return '$executableDirectory${Platform.pathSeparator}config.yaml';
}
