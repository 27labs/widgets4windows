# Widget Wall MVP

`Widget Wall` is a headless Dart controller for Windows 11 that:

- reads a `config.yaml` file,
- launches one process per configured widget entry,
- waits for each app's main window,
- snaps each window into a fullscreen grid on the primary display,
- keeps the managed windows pushed behind unrelated windows, and
- tears down all launched processes when the controller exits.

## Config

`config.yaml` uses one `widgets` entry per desired app instance:

```yaml
grid:
  rows: 2
  columns: 3

widgets:
  - exe: notepad.exe
    row: 0
    column: 0
    rowSpan: 1
    columnSpan: 1
    args: []
```

Supported fields per widget:

- `grid.padding`: optional pixel gap used both between windows and as the outer margin from the desktop edges. Defaults to `0`.
- `exe`: executable to launch.
- `args`: optional argument array.
- `row`, `column`: zero-based grid position.
- `rowSpan`, `columnSpan`: size in cells.
- `workingDirectory`: optional working directory for the process.
- `windowPollTimeoutMs`: optional timeout while waiting for the window to appear.

If the same executable appears multiple times, the controller launches one separate instance for each entry.

## Run

1. Install the Dart SDK on Windows.
2. Run `dart pub get`
3. Update `config.yaml`
4. Start the wall with `dart run bin/widget_wall.dart`

Pass a custom config path if needed:

```powershell
dart run bin/widget_wall.dart .\my-wall.yaml
```

## MVP Notes

- The MVP targets the primary monitor's desktop work area, so the taskbar is respected when it is visible.
- Windows are resized and moved, but not forcibly made borderless.
- The z-order is reinforced on a timer by pushing managed windows to the bottom.
- Cleanup is primarily enforced through a Windows Job Object with `KILL_ON_JOB_CLOSE`.
- Apps that create a separate top-level window per launch work best. Modern single-instance or tabbed apps (for example current Windows 11 Notepad in some configurations) may reuse an existing window instead of creating one window per process, which limits how independently they can be tiled.
