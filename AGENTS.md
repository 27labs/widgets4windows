## Flutter and Dart Command Execution

In this setup, the `flutter` and `dart` commands should be run outside the sandbox.

Reason:

- Flutter startup needs access to SDK Git metadata and writes to its own SDK cache.
- Sandboxed runs may hang or fail because that location is not fully accessible/writable inside the sandbox.

Policy:

- Do not tell the user to run routine `flutter` or `dart` commands manually just because they are outside the sandbox.
- Request an approval to run them outside the sandbox and execute them directly once approved.
- When possible, use a persistent prefix approval for `flutter` and `dart`.
- If permission has not yet been granted, trigger an approval request instead of stopping at instructions only.