import 'package:test/test.dart';
import 'package:widget_wall/src/windows_api.dart';

void main() {
  test('calculates a rectangle for a single grid cell', () {
    final layout = GridLayout(
      rows: 2,
      columns: 2,
      left: 0,
      top: 0,
      width: 200,
      height: 100,
      padding: 0,
    );

    final rect = layout.rectFor(
      row: 0,
      column: 0,
      rowSpan: 1,
      columnSpan: 1,
    );

    expect(rect.left, 0);
    expect(rect.top, 0);
    expect(rect.width, 100);
    expect(rect.height, 50);
  });

  test('applies outer and inter-cell padding', () {
    final layout = GridLayout(
      rows: 2,
      columns: 3,
      left: 0,
      top: 0,
      width: 320,
      height: 220,
      padding: 10,
    );

    final topLeft = layout.rectFor(
      row: 0,
      column: 0,
      rowSpan: 1,
      columnSpan: 1,
    );
    final bottomRight = layout.rectFor(
      row: 1,
      column: 2,
      rowSpan: 1,
      columnSpan: 1,
    );

    expect(
      [topLeft.left, topLeft.top, topLeft.width, topLeft.height],
      [10, 10, 93, 95],
    );
    expect(
      [
        bottomRight.left,
        bottomRight.top,
        bottomRight.width,
        bottomRight.height,
      ],
      [216, 115, 94, 95],
    );
  });

  test('calculates rectangles spanning multiple cells', () {
    final layout = GridLayout(
      rows: 2,
      columns: 3,
      left: 0,
      top: 0,
      width: 320,
      height: 220,
      padding: 10,
    );

    final rect = layout.rectFor(
      row: 0,
      column: 1,
      rowSpan: 2,
      columnSpan: 2,
    );

    expect([rect.left, rect.top, rect.width, rect.height], [113, 10, 197, 200]);
  });

  test('accepts the maximum padding that leaves one pixel per grid row', () {
    final layout = GridLayout(
      rows: 2,
      columns: 3,
      left: 0,
      top: 0,
      width: 1920,
      height: 1040,
      padding: 346,
    );

    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 3; column++) {
        final rect = layout.rectFor(
          row: row,
          column: column,
          rowSpan: 1,
          columnSpan: 1,
        );
        expect(rect.width, greaterThanOrEqualTo(1));
        expect(rect.height, greaterThanOrEqualTo(1));
      }
    }
  });

  test('rejects padding above the work-area threshold', () {
    expect(
      () => GridLayout(
        rows: 2,
        columns: 3,
        left: 0,
        top: 0,
        width: 1920,
        height: 1040,
        padding: 347,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          allOf(
            contains('grid.padding is 347'),
            contains('maximum is 346'),
            contains('1920x1040 primary work area'),
          ),
        ),
      ),
    );
  });

  test('rejects grids denser than the available pixels', () {
    expect(
      () => GridLayout(
        rows: 2,
        columns: 2000,
        left: 0,
        top: 0,
        width: 1920,
        height: 1040,
        padding: 0,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message.toString(),
          'message',
          allOf(
            contains('cannot provide at least one pixel per cell'),
            contains('grid.columns=2000'),
          ),
        ),
      ),
    );
  });
}
