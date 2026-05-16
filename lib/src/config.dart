import 'dart:io';

import 'package:yaml/yaml.dart';

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
    final yaml = loadYaml(raw) as YamlMap;

    final grid = yaml['grid'] as YamlMap? ??
        (throw FormatException('Missing grid block.'));
    final rows = _readPositiveInt(grid, 'rows');
    final columns = _readPositiveInt(grid, 'columns');
    final padding = _readNonNegativeInt(grid, 'padding', defaultValue: 0);

    final widgetList = yaml['widgets'] as YamlList? ??
        (throw FormatException('Missing widgets list.'));
    final widgets = widgetList
        .map((node) => WidgetEntry.fromYaml(node as YamlMap))
        .toList(growable: false);

    if (widgets.isEmpty) {
      throw FormatException('widgets must contain at least one entry.');
    }

    for (final widget in widgets) {
      final maxRow = widget.row + widget.rowSpan;
      final maxColumn = widget.column + widget.columnSpan;
      if (maxRow > rows || maxColumn > columns) {
        throw FormatException(
          'Widget "${widget.exe}" at row ${widget.row}, column ${widget.column} '
          'with span ${widget.rowSpan}x${widget.columnSpan} exceeds the $rows x $columns grid.',
        );
      }
    }

    return WallConfig(
      rows: rows,
      columns: columns,
      padding: padding,
      widgets: widgets,
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
    this.windowPollTimeout = const Duration(seconds: 27),
  });

  final String exe;
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;
  final List<String> arguments;
  final String? workingDirectory;
  final Duration windowPollTimeout;

  factory WidgetEntry.fromYaml(YamlMap yaml) {
    final exe = yaml['exe']?.toString();
    if (exe == null || exe.trim().isEmpty) {
      throw FormatException('Each widget must define a non-empty exe value.');
    }

    final args = (yaml['args'] as YamlList?)
            ?.map((value) => value.toString())
            .toList(growable: false) ??
        const <String>[];

    return WidgetEntry(
      exe: exe,
      row: _readNonNegativeInt(yaml, 'row'),
      column: _readNonNegativeInt(yaml, 'column'),
      rowSpan: _readPositiveInt(yaml, 'rowSpan'),
      columnSpan: _readPositiveInt(yaml, 'columnSpan'),
      arguments: args,
      workingDirectory: yaml['workingDirectory']?.toString(),
      windowPollTimeout: Duration(
        milliseconds: (yaml['windowPollTimeoutMs'] as int?) ?? 27000,
      ),
    );
  }
}

int _readPositiveInt(YamlMap yaml, String key) {
  final value = yaml[key];
  if (value is! int || value < 1) {
    throw FormatException('$key must be a positive integer.');
  }
  return value;
}

int _readNonNegativeInt(YamlMap yaml, String key, {int? defaultValue}) {
  final value = yaml[key];
  if (value == null) {
    if (defaultValue != null) return defaultValue;
    throw FormatException('$key must be a non-negative integer.');
  }
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}
