import 'dart:async';
import 'dart:io';

import 'package:widget_wall/src/config.dart';
import 'package:widget_wall/src/widget_wall_controller.dart';

Future<void> main(List<String> args) async {
  final configPath = args.isNotEmpty ? args.first : 'config.yaml';
  final config = await WallConfig.load(configPath);
  final controller = WidgetWallController(config: config);

  Future<void> shutdown() async {
    stderr.writeln('Shutting down widget wall...');
    await controller.dispose();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown()));
  if (!Platform.isWindows) {
    stderr.writeln('This MVP only supports Windows 11.');
    exitCode = 2;
    return;
  }

  try {
    await controller.start();
    stdout.writeln(
      'Widget Wall is running with ${config.widgets.length} configured app(s). '
      'Press Ctrl+C to stop.',
    );

    final done = Completer<void>();
    await done.future;
  } catch (error, stackTrace) {
    stderr.writeln('Widget Wall failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
    await controller.dispose();
  }
}
