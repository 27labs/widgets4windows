# Widgets4Windows Codebase Audit

Date: 2026-06-28  
Mode: Balanced, whole-codebase audit
Remediation status updated: 2026-06-28

## Scope

This audit covers the tracked Dart controller code, configuration, and project
documentation in this repository.

The `weather`, `habit_tracker`, and `pomodoro_timer` directories are Git
submodules. Their source was not available in the working tree, so their
implementations were excluded.

## Architecture

### Entry point

`bin/widget_wall.dart` loads the configuration, constructs the controller,
registers shutdown handling, and keeps the process alive.

### Main data flow

1. `WallConfig.load` reads and parses YAML configuration.
2. `WidgetWallController.start` validates the grid against the primary work
   area, then creates a Windows Job Object.
3. All configured executables are launched concurrently on the main isolate.
4. The Win32 layer polls for the process's visible top-level window.
5. `GridLayout` calculates the window bounds.
6. The window is hidden from the taskbar, placed in the grid, and periodically
   pushed to the bottom of the desktop z-order.
7. Shutdown closes the Job Object and sends close messages to managed windows.

### Ownership boundaries

- `lib/src/config.dart`: configuration parsing and grid-bound validation.
- `lib/src/widget_wall_controller.dart`: process lifecycle and orchestration.
- `lib/src/windows_api.dart`: compatibility barrel for Windows modules.
- `lib/src/windows/grid_layout.dart`: grid geometry and display-bound
  validation.
- `lib/src/windows/window_operations.dart`: window placement, discovery, and
  checked Win32 operations.
- `lib/src/windows/job_object.dart`: Windows Job Object lifecycle.
- `lib/src/windows_event_log.dart`: Windows Event Log integration.
- `bin/widget_wall.dart`: application startup, shutdown, and top-level errors.

## Baseline

| Gate | Result |
| --- | --- |
| `dart analyze` | Passed with no issues |
| `dart format --output=none --set-exit-if-changed .` | Passed; no changes |
| `dart test` | Passed; 25 tests |

## Summary

The audit identified 15 findings across configuration, lifecycle management,
native error handling, observability, performance, tests, and code structure.

| Severity | Count |
| --- | ---: |
| Critical | 3 |
| Suggested | 9 |
| Nit | 3 |

## Remediation status

The original findings and locations below are preserved as the pre-remediation
audit record. Their line references do not describe the reorganized source
layout.

| # | Status | Resolution |
| ---: | --- | --- |
| 1 | Resolved | Source-mode documentation now passes `config.yaml` explicitly; the intended compiled-executable default remains unchanged. |
| 2 | Accepted by design | Relative native executable paths are resolved through the controller's inherited `PATH`, matching terminal invocation. This contract and its shell-command limitations are documented. |
| 3 | Resolved | A Job Object assignment failure preserves the native error, kills the unassigned process immediately, and verifies termination before continuing. |
| 4 | Resolved | YAML values are explicitly validated, errors identify the first invalid configuration path, and timeouts must be positive. Missing and malformed files exit gracefully with descriptive Event Log entries. |
| 5 | Resolved | Fallible native operations report operation, HWND, and Win32 error details. Independent operations continue and retry with exponential backoff within each enforcement interval. `ShowWindow` is intentionally excluded because its return value reports prior visibility rather than success. |
| 6 | Deferred | Event Log remains the sole sink because the compiled application has no standard streams. Registration/reporting failure recovery was intentionally deferred. |
| 7 | Resolved | Widget launch and window discovery run concurrently, reducing startup toward the longest individual timeout. |
| 8 | Resolved | Window discovery uses short-lived isolate-local FFI callbacks and `Stopwatch`; global callback state was removed. |
| 9 | Resolved | The unreachable non-Windows guard was removed; the application is explicitly Windows-only. |
| 10 | Resolved | Grid padding is validated against the actual primary work area before Job Object creation or widget launch, guaranteeing at least one pixel per grid track. |
| 11 | Resolved | Expected `Process.start` failures are logged per widget and isolated so other widgets continue starting. |
| 12 | Resolved | Dart's `test` harness now covers YAML parsing and validation, timeout boundaries, grid geometry, padding thresholds, and configuration immutability. PATH behavior was verified separately at runtime. |
| 13 | Resolved | Configuration constructors defensively copy widget and argument lists into unmodifiable collections. |
| 14 | Resolved | The unused window-listing, PID lookup, and new-window discovery APIs and their orphaned state types were removed. |
| 15 | Resolved | Windows concerns were split under `lib/src/windows/`; `windows_api.dart` remains a compatibility barrel. |

| Outcome | Count |
| --- | ---: |
| Resolved | 13 |
| Accepted by design | 1 |
| Deferred | 1 |

## Critical findings

### 1. Default configuration lookup breaks documented `dart run` usage

**Location:** `bin/widget_wall.dart:19`, `bin/widget_wall.dart:45`

When running through `dart run`, `Platform.resolvedExecutable` points to the
Dart runtime rather than this project's executable. With no explicit argument,
the application therefore looks for `config.yaml` beside `dart.exe`, despite
the README instructing users to run:

```powershell
dart run bin/widget_wall.dart
```

The lookup strategy needs to distinguish development execution from a compiled
executable, with tests covering both path contracts.

### 2. Relative widget paths depend on the caller's working directory

**Location:** `lib/src/widget_wall_controller.dart:45`

`Process.start` receives each configured `exe` and `workingDirectory` as-is.
Relative values are consequently resolved against the process's current
working directory, not against the directory containing the loaded
configuration.

This makes an otherwise valid deployment fail when started from a shortcut,
the Run dialog, Task Scheduler, or another working directory. Relative paths
should have an explicit and documented base, preferably the configuration
directory.

### 3. Failed Job Object assignment can leave child processes running

**Location:** `lib/src/widget_wall_controller.dart:52`,
`lib/src/widget_wall_controller.dart:105`, `lib/src/widget_wall_controller.dart:115`

Failure to assign a launched process to the cleanup Job Object is reduced to a
warning, and the original error is discarded. Shutdown later sends `WM_CLOSE`,
but that operation is unchecked and is not a reliable termination fallback.

This violates the documented contract that all launched processes are torn
down when the controller exits. Preserve the assignment error and provide a
verified fallback for unassigned processes.

## Suggested findings

### 4. External YAML data relies on unsafe casts

**Location:** `lib/src/config.dart:22`, `lib/src/config.dart:24`,
`lib/src/config.dart:30`, `lib/src/config.dart:33`,
`lib/src/config.dart:87`, `lib/src/config.dart:101`

Malformed YAML shapes can produce `TypeError` rather than a field-specific
`FormatException`. In addition, `windowPollTimeoutMs` accepts zero and negative
integers, causing polling to fail immediately.

Validate each external value explicitly and report its configuration path in
the resulting error.

### 5. Native window operations ignore failure results

**Location:** `lib/src/windows_api.dart:140`,
`lib/src/windows_api.dart:154`, `lib/src/windows_api.dart:172`,
`lib/src/windows_api.dart:186`

The results of `ShowWindow`, `SetWindowPos`, `SetWindowLongPtr`, and
`PostMessage` are not checked. The controller can therefore report that it is
running while placement, taskbar hiding, z-order enforcement, or shutdown is
silently failing.

Wrap the relevant operations with checked errors that include the operation,
window handle, and `GetLastError` value where applicable.

### 6. Event Log failures are silent

**Location:** `lib/src/windows_event_log.dart:99`,
`lib/src/windows_event_log.dart:103`

Failure to register an event source causes an immediate silent return, and the
result from `ReportEventW` is ignored. This is the application's only
observability sink, so its own failure removes all diagnostic evidence.

Add a minimal fallback sink, such as stderr when available, and preserve native
error details.

### 7. Startup latency scales with the sum of widget timeouts

**Location:** `lib/src/widget_wall_controller.dart:44`,
`lib/src/widget_wall_controller.dart:54`

Each process is launched and awaited before the next widget starts. With the
default 27-second timeout, four widgets that fail to expose matching windows
can delay startup by roughly 108 seconds, in addition to the initial delay.

Concurrent discovery would reduce the total toward the longest individual
timeout, but it first requires removing the global, non-reentrant search state
described below.

### 8. Window discovery uses global, non-reentrant state

**Location:** `lib/src/windows_api.dart:272`,
`lib/src/windows_api.dart:286`, `lib/src/windows_api.dart:334`,
`lib/src/windows_api.dart:356`

The FFI callback communicates through `_activeWindowSearch`. Concurrent calls
can overwrite one another, and an unexpected exception can leave stale state.
The two wait functions also duplicate nearly identical polling loops.

Encapsulate enumeration state behind one serialized or otherwise reentrant
search abstraction before parallelizing startup.

### 9. The non-Windows guard may not execute

**Location:** `bin/widget_wall.dart:9`, `bin/widget_wall.dart:11`,
`lib/src/windows_event_log.dart:47`

`advapi32.dll` is opened during library initialization. On a non-Windows
platform, that initialization can fail before `main` reaches its
`Platform.isWindows` check.

Load the native library lazily after platform validation, or remove the
unreachable graceful-error promise.

### 10. Excessive padding can produce invalid geometry

**Location:** `lib/src/windows_api.dart:88`

The available track area is clamped, but padding itself is not bounded against
the display size. A large configured padding can therefore place zero-sized or
off-screen rectangles beyond the work area.

Validate the layout using the actual display dimensions before launching
widgets and provide a clear configuration error.

### 11. Process-launch errors abort the entire wall

**Location:** `lib/src/widget_wall_controller.dart:44`

A missing executable or invalid working directory throws out of `start` and
tears down every widget, while a window timeout only skips the affected
widget. The inconsistent policy is not documented.

Choose and document either transactional startup or per-widget isolation. If
isolation is intended, log executable-specific failures and continue.

### 12. There is no automated test harness

**Location:** `pubspec.yaml`

The package does not depend on Dart's `test` package and contains no tests.
Configuration parsing and grid geometry are both deterministic units that can
be covered without invoking Win32.

Before behavior-adjacent fixes, add a test runner and establish coverage for:

- valid and invalid YAML shapes;
- timeout and grid boundaries;
- grid rectangle calculations;
- development and compiled configuration-path behavior;
- relative executable-path resolution.

## Nit findings

### 13. Configuration collections remain mutable

**Location:** `lib/src/config.dart:18`, `lib/src/config.dart:77`

The configuration model presents final list references, but callers can still
replace elements. Immutable views would better match the value-object design.

### 14. Several window APIs have no repository callers

**Location:** `lib/src/windows_api.dart:315`,
`lib/src/windows_api.dart:324`, `lib/src/windows_api.dart:356`

`listVisibleTopLevelWindows`, `getWindowProcessId`, and
`waitForNewTopLevelWindow` are unused within this repository. Confirm whether
they are retained package APIs; otherwise remove them after tests establish
the intended discovery behavior.

### 15. `windows_api.dart` mixes several independent concerns

**Location:** `lib/src/windows_api.dart`

At 446 lines, this file combines grid geometry, window placement, window
enumeration, native structure definitions, and Job Object lifecycle. These
concerns have natural test and ownership seams.

After behavior fixes are covered, split the file into focused modules. File
movement should be a separate change so it does not obscure functional diffs.

## Refactoring strategy

1. Add the Dart test harness and establish a green smoke test.
2. Add tests for configuration parsing, path resolution, and grid geometry.
3. Correct default and relative path resolution.
4. Harden YAML validation and layout constraints.
5. Make process cleanup reliable and preserve assignment errors.
6. Check and report native operation failures.
7. Replace global window-search state, then evaluate concurrent startup.
8. Split `windows_api.dart` along its established ownership seams.

## Audit status

Remediation is complete for every finding except finding 6, which is explicitly
deferred. The automated baseline is green with analysis, formatting, and all
25 tests passing.
