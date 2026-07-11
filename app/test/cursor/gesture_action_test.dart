import 'package:air_pointer_app/src/cursor/gesture_action_executor.dart';
import 'package:air_pointer_app/src/cursor/system_shortcut.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GestureAction encode/decode', () {
    test('SystemShortcutAction round-trips', () {
      for (final shortcut in SystemShortcut.values) {
        final action = SystemShortcutAction(shortcut);
        final decoded = GestureAction.decode(action.encode());
        expect(decoded, isA<SystemShortcutAction>());
        expect((decoded! as SystemShortcutAction).shortcut, shortcut);
      }
    });

    test('OpenAppAction round-trips', () {
      const action = OpenAppAction('/Applications/Safari.app');
      final decoded = GestureAction.decode(action.encode());
      expect(decoded, isA<OpenAppAction>());
      expect((decoded! as OpenAppAction).appPath, '/Applications/Safari.app');
    });

    test('RunCommandAction round-trips with arguments', () {
      const action = RunCommandAction('/usr/bin/say', ['hello', 'world']);
      final decoded = GestureAction.decode(action.encode());
      expect(decoded, isA<RunCommandAction>());
      final runCommand = decoded! as RunCommandAction;
      expect(runCommand.executable, '/usr/bin/say');
      expect(runCommand.arguments, ['hello', 'world']);
    });

    test('RunCommandAction round-trips with no arguments', () {
      const action = RunCommandAction('/usr/bin/say');
      final decoded = GestureAction.decode(action.encode());
      expect(decoded, isA<RunCommandAction>());
      expect((decoded! as RunCommandAction).arguments, isEmpty);
    });

    test('decode returns null for malformed JSON', () {
      expect(GestureAction.decode('not json'), isNull);
    });

    test('decode returns null for valid JSON with unknown type', () {
      expect(GestureAction.decode('{"type": "somethingElse"}'), isNull);
    });

    test('decode returns null for a JSON array, not an object', () {
      expect(GestureAction.decode('[1, 2, 3]'), isNull);
    });

    test('decode returns null for openApp with empty path', () {
      expect(GestureAction.decode('{"type": "openApp", "appPath": ""}'), isNull);
    });

    test('decode returns null for runCommand with missing executable', () {
      expect(GestureAction.decode('{"type": "runCommand"}'), isNull);
    });

    test('decode returns null for shortcut with unrecognized name', () {
      expect(GestureAction.decode('{"type": "shortcut", "shortcut": "doesNotExist"}'), isNull);
    });
  });

  group('GestureAction.label', () {
    test('OpenAppAction strips the .app suffix', () {
      expect(const OpenAppAction('/Applications/Safari.app').label, 'Open Safari');
    });

    test('OpenAppAction without a .app suffix uses the raw filename', () {
      expect(const OpenAppAction('/usr/local/bin/mytool').label, 'Open mytool');
    });

    test('RunCommandAction uses the executable basename', () {
      expect(const RunCommandAction('/usr/bin/say').label, 'Run say');
    });
  });
}
