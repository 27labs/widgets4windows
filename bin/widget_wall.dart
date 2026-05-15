import 'dart:async';
import 'dart:io';

import 'package:widget_wall/src/config.dart';
import 'package:widget_wall/src/widget_wall_controller.dart';
import 'package:widget_wall/src/windows_event_log.dart';

Future<void> main(List<String> args) async {
  final eventLog = WindowsEventLog();

  if (!Platform.isWindows) {
    eventLog.error('This MVP only supports Windows 11.');
    exitCode = 2;
    return;
  }

  WidgetWallController? controller;
  try {
    final configPath = args.isNotEmpty ? args.first : _defaultConfigPath();
    final config = await WallConfig.load(configPath);
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
