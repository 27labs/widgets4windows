import 'dart:io';

import 'package:yaml/yaml.dart';

const Duration _defaultWindowPollTimeout = Duration(seconds: 27);

class WallConfig {
  WallConfig({
    required this.rows,
    required this.columns,
    required this.padding,
    required this.widgets,
  });

  final int rows;
  final int columns;
  final int padding;
  final List<WidgetEntry> widgets;

  static Future<WallConfig> load(String path) async {
    final raw = await File(path).readAsString();
    final Object? document;
    try {
      document = loadYaml(raw);
    } on FormatException catch (error) {
      throw FormatException('Invalid YAML syntax: $error');
    }

    if (document is! YamlMap) {
      throw const FormatException('Configuration root must be a map.');
    }

    final grid = _readRequiredMap(document, 'grid', path: 'grid');
    final rows = _readPositiveInt(grid, 'rows', path: 'grid.rows');
    final columns = _readPositiveInt(
      grid,
      'columns',
      path: 'grid.columns',
    );
    final padding = _readNonNegativeInt(
      grid,
      'padding',
      path: 'grid.padding',
      defaultValue: 0,
    );

    final widgetList = _readRequiredList(
      document,
      'widgets',
      path: 'widgets',
    );
    final widgets = <WidgetEntry>[];
    for (var index = 0; index < widgetList.length; index++) {
      final path = 'widgets[$index]';
      final node = widgetList[index];
      if (node is! YamlMap) {
        throw FormatException('$path must be a map.');
      }
      widgets.add(WidgetEntry.fromYaml(node, path: path));
    }

    if (widgets.isEmpty) {
      throw const FormatException(
        'widgets must contain at least one entry.',
      );
    }

    for (var index = 0; index < widgets.length; index++) {
      final widget = widgets[index];
      final maxRow = widget.row + widget.rowSpan;
      final maxColumn = widget.column + widget.columnSpan;
      if (maxRow > rows || maxColumn > columns) {
        throw FormatException(
          'widgets[$index] ("${widget.exe}") at row ${widget.row}, '
          'column ${widget.column} '
          'with span ${widget.rowSpan}x${widget.columnSpan} exceeds the $rows x $columns grid.',
        );
      }
    }

    return WallConfig(
      rows: rows,
      columns: columns,
      padding: padding,
      widgets: widgets.toList(growable: false),
    );
  }
}

class WidgetEntry {
  WidgetEntry({
    required this.exe,
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.columnSpan,
    required this.arguments,
    this.workingDirectory,
    this.windowPollTimeout = _defaultWindowPollTimeout,
  });

  final String exe;
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;
  final List<String> arguments;
  final String? workingDirectory;
  final Duration windowPollTimeout;

  factory WidgetEntry.fromYaml(YamlMap yaml, {required String path}) {
    final exe = _readNonEmptyString(yaml, 'exe', path: '$path.exe');
    final args = _readStringList(yaml, 'args', path: '$path.args');

    return WidgetEntry(
      exe: exe,
      row: _readNonNegativeInt(yaml, 'row', path: '$path.row'),
      column: _readNonNegativeInt(yaml, 'column', path: '$path.column'),
      rowSpan: _readPositiveInt(yaml, 'rowSpan', path: '$path.rowSpan'),
      columnSpan: _readPositiveInt(
        yaml,
        'columnSpan',
        path: '$path.columnSpan',
      ),
      arguments: args,
      workingDirectory: _readOptionalNonEmptyString(
        yaml,
        'workingDirectory',
        path: '$path.workingDirectory',
      ),
      windowPollTimeout: Duration(
        milliseconds: _readPositiveInt(
          yaml,
          'windowPollTimeoutMs',
          path: '$path.windowPollTimeoutMs',
          defaultValue: _defaultWindowPollTimeout.inMilliseconds,
        ),
      ),
    );
  }
}

YamlMap _readRequiredMap(YamlMap yaml, String key, {required String path}) {
  final value = yaml[key];
  if (value == null) {
    throw FormatException('Missing required configuration value: $path.');
  }
  if (value is! YamlMap) {
    throw FormatException('$path must be a map.');
  }
  return value;
}

YamlList _readRequiredList(YamlMap yaml, String key, {required String path}) {
  final value = yaml[key];
  if (value == null) {
    throw FormatException('Missing required configuration value: $path.');
  }
  if (value is! YamlList) {
    throw FormatException('$path must be a list.');
  }
  return value;
}

String _readNonEmptyString(
  YamlMap yaml,
  String key, {
  required String path,
}) {
  final value = yaml[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  return value;
}

String? _readOptionalNonEmptyString(
  YamlMap yaml,
  String key, {
  required String path,
}) {
  final value = yaml[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  return value;
}

List<String> _readStringList(
  YamlMap yaml,
  String key, {
  required String path,
}) {
  final value = yaml[key];
  if (value == null) return const <String>[];
  if (value is! YamlList) {
    throw FormatException('$path must be a list.');
  }

  final result = <String>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is! String) {
      throw FormatException('$path[$index] must be a string.');
    }
    result.add(item);
  }
  return result.toList(growable: false);
}

int _readPositiveInt(
  YamlMap yaml,
  String key, {
  required String path,
  int? defaultValue,
}) {
  final value = yaml[key];
  if (value == null && defaultValue != null) return defaultValue;
  if (value is! int || value < 1) {
    throw FormatException('$path must be a positive integer.');
  }
  return value;
}

int _readNonNegativeInt(
  YamlMap yaml,
  String key, {
  required String path,
  int? defaultValue,
}) {
  final value = yaml[key];
  if (value == null) {
    if (defaultValue != null) return defaultValue;
    throw FormatException('$path must be a non-negative integer.');
  }
  if (value is! int || value < 0) {
    throw FormatException('$path must be a non-negative integer.');
  }
  return value;
}
