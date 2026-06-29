import 'dart:io';

import 'package:test/test.dart';
import 'package:widget_wall/src/config.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'widget-wall-config-test',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  Future<String> writeConfig(String contents) async {
    final file = File('${tempDirectory.path}/config.yaml');
    await file.writeAsString(contents);
    return file.path;
  }

  test('loads valid configuration with defaults', () async {
    final path = await writeConfig('''
grid:
  rows: 2
  columns: 3
widgets:
  - exe: notepad.exe
    row: 0
    column: 1
    rowSpan: 1
    columnSpan: 2
''');

    final config = await WallConfig.load(path);

    expect(config.rows, 2);
    expect(config.columns, 3);
    expect(config.padding, 0);
    expect(config.widgets, hasLength(1));
    expect(config.widgets.single.arguments, isEmpty);
    expect(config.widgets.single.workingDirectory, isNull);
    expect(
      config.widgets.single.windowPollTimeout,
      const Duration(seconds: 27),
    );
  });

  test('loads optional widget values', () async {
    final path = await writeConfig(r'''
grid:
  rows: 1
  columns: 1
  padding: 8
widgets:
  - exe: tool.exe
    args:
      - --mode
      - compact
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
    workingDirectory: C:\Widgets
    windowPollTimeoutMs: 1270
''');

    final config = await WallConfig.load(path);
    final widget = config.widgets.single;

    expect(config.padding, 8);
    expect(widget.arguments, ['--mode', 'compact']);
    expect(widget.workingDirectory, r'C:\Widgets');
    expect(widget.windowPollTimeout, const Duration(milliseconds: 1270));
  });

  test('defensively copies and exposes unmodifiable collections', () {
    final sourceArguments = <String>['--mode'];
    final widget = WidgetEntry(
      exe: 'tool.exe',
      row: 0,
      column: 0,
      rowSpan: 1,
      columnSpan: 1,
      arguments: sourceArguments,
    );
    final sourceWidgets = <WidgetEntry>[widget];
    final config = WallConfig(
      rows: 1,
      columns: 1,
      padding: 0,
      widgets: sourceWidgets,
    );

    sourceArguments.add('compact');
    sourceWidgets.clear();

    expect(widget.arguments, ['--mode']);
    expect(config.widgets, [same(widget)]);
    expect(() => widget.arguments.add('compact'), throwsUnsupportedError);
    expect(() => widget.arguments[0] = '--other', throwsUnsupportedError);
    expect(() => config.widgets.add(widget), throwsUnsupportedError);
    expect(() => config.widgets[0] = widget, throwsUnsupportedError);
  });

  test('reports a missing configuration file', () async {
    final path = '${tempDirectory.path}/missing.yaml';

    await expectLater(
      WallConfig.load(path),
      throwsA(isA<PathNotFoundException>()),
    );
  });

  test('reports malformed YAML syntax', () async {
    final path = await writeConfig('grid: [');

    await expectLater(
      WallConfig.load(path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          allOf(contains('Invalid YAML syntax:'), contains('line 1')),
        ),
      ),
    );
  });

  test('requires the configuration root to be a map', () async {
    final path = await writeConfig('- item');

    await _expectFormatError(
      path,
      'Configuration root must be a map.',
    );
  });

  for (final testCase in [
    (
      name: 'requires a grid block',
      yaml: 'widgets: []',
      message: 'Missing required configuration value: grid.',
    ),
    (
      name: 'requires grid to be a map',
      yaml: 'grid: invalid\nwidgets: []',
      message: 'grid must be a map.',
    ),
    (
      name: 'requires a widgets list',
      yaml: 'grid:\n  rows: 1\n  columns: 1',
      message: 'Missing required configuration value: widgets.',
    ),
    (
      name: 'requires widgets to be a list',
      yaml: 'grid:\n  rows: 1\n  columns: 1\nwidgets: invalid',
      message: 'widgets must be a list.',
    ),
  ]) {
    test(testCase.name, () async {
      final path = await writeConfig(testCase.yaml);
      await _expectFormatError(path, testCase.message);
    });
  }

  test('rejects negative grid padding', () async {
    final path = await writeConfig('''
grid:
  rows: 1
  columns: 1
  padding: -1
widgets: []
''');

    await _expectFormatError(
      path,
      'grid.padding must be a non-negative integer.',
    );
  });

  test('reports the first invalid field by configuration path', () async {
    final path = await writeConfig('''
grid:
  rows: invalid
  columns: 1
widgets: invalid
''');

    await _expectFormatError(
      path,
      'grid.rows must be a positive integer.',
    );
  });

  test('requires every widget entry to be a map', () async {
    final path = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - invalid
''');

    await _expectFormatError(path, 'widgets[0] must be a map.');
  });

  test('requires executable and argument values to be strings', () async {
    final invalidExecutable = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - exe: 42
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
''');
    await _expectFormatError(
      invalidExecutable,
      'widgets[0].exe must be a non-empty string.',
    );

    final invalidArgument = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - exe: tool.exe
    args: [valid, 42]
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
''');
    await _expectFormatError(
      invalidArgument,
      'widgets[0].args[1] must be a string.',
    );

    final invalidArguments = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - exe: tool.exe
    args: invalid
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
''');
    await _expectFormatError(
      invalidArguments,
      'widgets[0].args must be a list.',
    );
  });

  test('requires a non-empty working directory when provided', () async {
    final path = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - exe: tool.exe
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
    workingDirectory: ''
''');

    await _expectFormatError(
      path,
      'widgets[0].workingDirectory must be a non-empty string.',
    );
  });

  for (final timeout in [0, -1, 'invalid']) {
    test('rejects windowPollTimeoutMs value $timeout', () async {
      final path = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - exe: tool.exe
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
    windowPollTimeoutMs: $timeout
''');

      await _expectFormatError(
        path,
        'widgets[0].windowPollTimeoutMs must be a positive integer.',
      );
    });
  }

  test('rejects widgets that exceed the configured grid', () async {
    final path = await writeConfig('''
grid:
  rows: 1
  columns: 1
widgets:
  - exe: tool.exe
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 2
''');

    await expectLater(
      WallConfig.load(path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          allOf(contains('widgets[0]'), contains('exceeds the 1 x 1 grid')),
        ),
      ),
    );
  });
}

Future<void> _expectFormatError(String path, String expectedMessage) async {
  await expectLater(
    WallConfig.load(path),
    throwsA(
      isA<FormatException>().having(
        (error) => error.message.toString(),
        'message',
        expectedMessage,
      ),
    ),
  );
}
