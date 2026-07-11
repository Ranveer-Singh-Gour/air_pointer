import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../native/cursor_backend.dart';
import 'system_shortcut.dart';

/// An action a discrete hand gesture (or a swipe/pinch approximation) can
/// trigger. Three kinds:
/// - [SystemShortcutAction]: a built-in OS shortcut, no configuration —
///   each [CursorBackend] maps it to its own platform's actual keys.
/// - [OpenAppAction]: launches an app by path (`.app` bundle on macOS,
///   executable/shortcut on Windows).
/// - [RunCommandAction]: runs a user-specified executable with arguments.
///
/// The latter two run arbitrary local commands — safe only because the
/// binding is authored by the same user who'll trigger it (Settings screen),
/// the same trust model as a keyboard-shortcut launcher (Alfred, Raycast).
/// Never construct these from untrusted input.
sealed class GestureAction {
  const GestureAction();

  String get label;

  /// Encodes to a JSON string for [AppSettingsStore] persistence.
  String encode() => jsonEncode(_toJson());

  Object _toJson();

  /// Decodes a string produced by [encode]. Returns `null` for malformed
  /// input (e.g. a stale format from a previous app version) rather than
  /// throwing, since a bad stored value shouldn't crash startup.
  static GestureAction? decode(String value) {
    try {
      final json = jsonDecode(value);
      if (json is! Map) return null;
      final type = json['type'];
      switch (type) {
        case 'shortcut':
          final name = json['shortcut'];
          for (final shortcut in SystemShortcut.values) {
            if (shortcut.name == name) return SystemShortcutAction(shortcut);
          }
          return null;
        case 'openApp':
          final path = json['appPath'];
          return path is String && path.isNotEmpty ? OpenAppAction(path) : null;
        case 'runCommand':
          final executable = json['executable'];
          final args = json['arguments'];
          if (executable is! String || executable.isEmpty) return null;
          final arguments = (args is List ? args : const []).whereType<String>().toList();
          return RunCommandAction(executable, arguments);
        default:
          return null;
      }
    } on FormatException {
      return null;
    }
  }
}

final class SystemShortcutAction extends GestureAction {
  const SystemShortcutAction(this.shortcut);

  final SystemShortcut shortcut;

  @override
  String get label => shortcut.label;

  @override
  Object _toJson() => {'type': 'shortcut', 'shortcut': shortcut.name};
}

final class OpenAppAction extends GestureAction {
  const OpenAppAction(this.appPath);

  /// Absolute path to launch — a `.app` bundle on macOS, an executable or
  /// `.lnk` shortcut on Windows.
  final String appPath;

  @override
  String get label {
    final name = appPath.split(RegExp(r'[\\/]')).last;
    return 'Open ${name.endsWith('.app') ? name.substring(0, name.length - 4) : name}';
  }

  @override
  Object _toJson() => {'type': 'openApp', 'appPath': appPath};
}

final class RunCommandAction extends GestureAction {
  const RunCommandAction(this.executable, [this.arguments = const []]);

  final String executable;
  final List<String> arguments;

  @override
  String get label => 'Run ${executable.split(RegExp(r'[\\/]')).last}';

  @override
  Object _toJson() => {'type': 'runCommand', 'executable': executable, 'arguments': arguments};
}

/// Runs a [GestureAction] via [CursorBackend] (for [SystemShortcutAction] /
/// [OpenAppAction]) or a direct process spawn (for [RunCommandAction], which
/// is already OS-agnostic through `dart:io`). Stateless — safe to share one
/// instance.
class GestureActionExecutor {
  GestureActionExecutor([CursorBackend? backend]) : _backend = backend ?? CursorBackend.instance;

  final CursorBackend _backend;

  void run(GestureAction action) {
    switch (action) {
      case SystemShortcutAction(:final shortcut):
        _backend.triggerShortcut(shortcut);

      case OpenAppAction(:final appPath):
        _backend.openApp(appPath);

      case RunCommandAction(:final executable, :final arguments):
        // Arguments are passed as an argv array, not interpolated into a
        // shell string, so this isn't shell-injectable even though the
        // values ultimately come from user-typed Settings input.
        unawaited(Process.run(executable, arguments));
    }
  }
}
