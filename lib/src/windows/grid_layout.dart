class DisplayBounds {
  const DisplayBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

class GridRect {
  const GridRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

class GridLayout {
  GridLayout({
    required this.rows,
    required this.columns,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.padding,
  }) {
    if (width < columns || height < rows) {
      throw FormatException(
        'The ${width}x$height primary work area cannot provide at least one '
        'pixel per cell for grid.rows=$rows and grid.columns=$columns.',
      );
    }

    final maxHorizontalPadding = (width - columns) ~/ (columns + 1);
    final maxVerticalPadding = (height - rows) ~/ (rows + 1);
    final maxPadding = maxHorizontalPadding < maxVerticalPadding
        ? maxHorizontalPadding
        : maxVerticalPadding;
    if (padding > maxPadding) {
      throw FormatException(
        'grid.padding is $padding, but its maximum is $maxPadding for a '
        '${rows}x$columns grid in the ${width}x$height primary work area.',
      );
    }
  }

  final int rows;
  final int columns;
  final int left;
  final int top;
  final int width;
  final int height;
  final int padding;

  GridRect rectFor({
    required int row,
    required int column,
    required int rowSpan,
    required int columnSpan,
  }) {
    final trackWidth =
        (width - (padding * 2) - (padding * (columns - 1))).clamp(0, width);
    final trackHeight =
        (height - (padding * 2) - (padding * (rows - 1))).clamp(0, height);
    final rectLeft = left +
        padding +
        ((column * trackWidth) ~/ columns) +
        (column * padding);
    final rectTop =
        top + padding + ((row * trackHeight) ~/ rows) + (row * padding);
    final rectRight = left +
        padding +
        (((column + columnSpan) * trackWidth) ~/ columns) +
        ((column + columnSpan - 1) * padding);
    final rectBottom = top +
        padding +
        (((row + rowSpan) * trackHeight) ~/ rows) +
        ((row + rowSpan - 1) * padding);

    return GridRect(
      left: rectLeft,
      top: rectTop,
      width: rectRight - rectLeft,
      height: rectBottom - rectTop,
    );
  }
}
