import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

import '../cursor/gesture_action_executor.dart';
import '../cursor/gesture_session_controller.dart';
import '../cursor/system_shortcut.dart';
import '../native/launch_at_login.dart';
import '../native/panic_hotkey.dart';
import '../storage/app_settings_store.dart';

/// Settings — persisted via [store], with a subset (click sound, gesture
/// action bindings) pushed live to [getActiveController] if cursor control
/// happens to be on while this is open.
///
/// [swipeGesturesEnabled]/[twoHandZoomEnabled] are NOT live-applied: both
/// configure the underlying `GestureInputSource` at construction
/// (`swipeThreshold`/`maxHands`), so a change here only takes effect the
/// next time cursor control is turned on.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.store,
    required this.getActiveController,
    required this.onPanic,
    super.key,
  });

  final AppSettingsStore store;
  final GestureSessionController? Function() getActiveController;

  /// Registered as the panic hotkey's handler when the toggle here turns it
  /// back on — the same handler `main.dart` uses at startup, so re-enabling
  /// from Settings behaves identically to the initial registration (fully
  /// stops tracking, not just cursor control — see `_AirPointerAppState._disable`).
  final VoidCallback onPanic;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _launchAtLogin = false;
  bool _clickSound = true;
  bool _swipeGestures = false;
  bool _twoHandZoom = false;
  bool _panicHotkey = true;
  final Map<RecognizedGesture, GestureAction?> _gestureActions = {};

  static const _bindableGestures = [
    RecognizedGesture.closedFist,
    RecognizedGesture.openPalm,
    RecognizedGesture.pointingUp,
    RecognizedGesture.thumbUp,
    RecognizedGesture.thumbDown,
    RecognizedGesture.victory,
    RecognizedGesture.iLoveYou,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final store = widget.store;
    final launchAtLogin = await LaunchAtLogin.isEnabled();
    final clickSound = await store.loadClickSoundEnabled();
    final swipe = await store.loadSwipeGesturesEnabled();
    final zoom = await store.loadTwoHandZoomEnabled();
    final panic = await store.loadPanicHotkeyEnabled();
    final actions = <RecognizedGesture, GestureAction?>{};
    for (final gesture in _bindableGestures) {
      actions[gesture] = await store.loadGestureAction(gesture);
    }
    if (!mounted) return;
    setState(() {
      _launchAtLogin = launchAtLogin;
      _clickSound = clickSound;
      _swipeGestures = swipe;
      _twoHandZoom = zoom;
      _panicHotkey = panic;
      _gestureActions
        ..clear()
        ..addAll(actions);
      _loading = false;
    });
  }

  Future<void> _setLaunchAtLogin(bool value) async {
    setState(() => _launchAtLogin = value);
    await LaunchAtLogin.setEnabled(value);
    await widget.store.saveLaunchAtLogin(value);
  }

  Future<void> _setClickSound(bool value) async {
    setState(() => _clickSound = value);
    await widget.store.saveClickSoundEnabled(value);
    widget.getActiveController()?.setClickSoundEnabled(value);
  }

  Future<void> _setSwipeGestures(bool value) async {
    setState(() => _swipeGestures = value);
    await widget.store.saveSwipeGesturesEnabled(value);
  }

  Future<void> _setTwoHandZoom(bool value) async {
    setState(() => _twoHandZoom = value);
    await widget.store.saveTwoHandZoomEnabled(value);
  }

  Future<void> _setPanicHotkey(bool value) async {
    setState(() => _panicHotkey = value);
    await widget.store.savePanicHotkeyEnabled(value);
    if (value) {
      await PanicHotkey.register(widget.onPanic);
    } else {
      await PanicHotkey.unregister();
    }
  }

  Future<void> _setGestureAction(RecognizedGesture gesture, GestureAction? action) async {
    setState(() => _gestureActions[gesture] = action);
    await widget.store.saveGestureAction(gesture, action);
    widget.getActiveController()?.setGestureAction(gesture, action);
  }

  Future<void> _editGestureAction(RecognizedGesture gesture) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _GestureActionEditDialog(initial: _gestureActions[gesture]),
    );
    if (result != null) await _setGestureAction(gesture, result.action);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0F),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0F),
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionLabel('General'),
          _SwitchTile(
            title: 'Open at login',
            subtitle: 'Start air_pointer_app automatically when you sign in.',
            value: _launchAtLogin,
            onChanged: _setLaunchAtLogin,
          ),
          _SwitchTile(
            title: 'Click sound',
            subtitle: 'Play a sound when a pinch registers as a click.',
            value: _clickSound,
            onChanged: _setClickSound,
          ),
          _SwitchTile(
            title: 'Panic hotkey',
            subtitle: '${PanicHotkey.label} instantly turns off cursor control.',
            value: _panicHotkey,
            onChanged: _setPanicHotkey,
          ),
          const SizedBox(height: 24),
          _SectionLabel('Gestures (experimental)'),
          _SwitchTile(
            title: 'Swipe → space switching',
            subtitle: 'A fast swipe moves between Spaces / opens Mission Control. '
                'Applies next time cursor control is turned on.',
            value: _swipeGestures,
            onChanged: _setSwipeGestures,
          ),
          _SwitchTile(
            title: 'Two-hand pinch to zoom',
            subtitle: 'Approximated with Cmd+scroll zoom steps, not a continuous pinch — '
                'macOS has no public API for synthetic trackpad gestures. '
                'Applies next time cursor control is turned on.',
            value: _twoHandZoom,
            onChanged: _setTwoHandZoom,
          ),
          const SizedBox(height: 24),
          _SectionLabel('Gesture actions'),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Bind a hand pose to a system shortcut, an app to open, or a '
              'command to run. Unbound gestures do nothing.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          for (final gesture in _bindableGestures)
            _GestureActionRow(
              gesture: gesture,
              value: _gestureActions[gesture],
              onTap: () => _editGestureAction(gesture),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

const _gestureLabels = {
  RecognizedGesture.closedFist: 'Closed fist ✊',
  RecognizedGesture.openPalm: 'Open palm 🖐',
  RecognizedGesture.pointingUp: 'Pointing up ☝',
  RecognizedGesture.thumbUp: 'Thumbs up 👍',
  RecognizedGesture.thumbDown: 'Thumbs down 👎',
  RecognizedGesture.victory: 'Victory ✌',
  RecognizedGesture.iLoveYou: 'I love you 🤙',
};

class _GestureActionRow extends StatelessWidget {
  const _GestureActionRow({
    required this.gesture,
    required this.value,
    required this.onTap,
  });

  final RecognizedGesture gesture;
  final GestureAction? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _gestureLabels[gesture] ?? gesture.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              Text(
                value?.label ?? 'None',
                style: TextStyle(color: value == null ? Colors.white38 : Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
            ],
          ),
        ),
      );
}

// ── Gesture-action edit dialog ──────────────────────────────────────────────

enum _Kind { none, shortcut, openApp, runCommand }

class _EditResult {
  const _EditResult(this.action);
  final GestureAction? action;
}

class _GestureActionEditDialog extends StatefulWidget {
  const _GestureActionEditDialog({this.initial});
  final GestureAction? initial;

  @override
  State<_GestureActionEditDialog> createState() => _GestureActionEditDialogState();
}

class _GestureActionEditDialogState extends State<_GestureActionEditDialog> {
  late _Kind _kind = switch (widget.initial) {
    null => _Kind.none,
    SystemShortcutAction() => _Kind.shortcut,
    OpenAppAction() => _Kind.openApp,
    RunCommandAction() => _Kind.runCommand,
  };
  late SystemShortcut _shortcut =
      widget.initial is SystemShortcutAction ? (widget.initial! as SystemShortcutAction).shortcut : SystemShortcut.values.first;
  late final _appPathController =
      TextEditingController(text: widget.initial is OpenAppAction ? (widget.initial! as OpenAppAction).appPath : '');
  late final _commandController = TextEditingController(
      text: widget.initial is RunCommandAction ? (widget.initial! as RunCommandAction).executable : '');
  late final _argsController = TextEditingController(
      text: widget.initial is RunCommandAction ? (widget.initial! as RunCommandAction).arguments.join(' ') : '');

  @override
  void dispose() {
    _appPathController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  GestureAction? _buildAction() => switch (_kind) {
        _Kind.none => null,
        _Kind.shortcut => SystemShortcutAction(_shortcut),
        _Kind.openApp => _appPathController.text.trim().isEmpty ? null : OpenAppAction(_appPathController.text.trim()),
        _Kind.runCommand => _commandController.text.trim().isEmpty
            ? null
            : RunCommandAction(
                _commandController.text.trim(),
                _argsController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(),
              ),
      };

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gesture action', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                DropdownButton<_Kind>(
                  isExpanded: true,
                  value: _kind,
                  dropdownColor: const Color(0xFF1C1C1E),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: _Kind.none, child: Text('None')),
                    DropdownMenuItem(value: _Kind.shortcut, child: Text('System shortcut')),
                    DropdownMenuItem(value: _Kind.openApp, child: Text('Open an app')),
                    DropdownMenuItem(value: _Kind.runCommand, child: Text('Run a command')),
                  ],
                  onChanged: (kind) => setState(() => _kind = kind ?? _Kind.none),
                ),
                const SizedBox(height: 12),
                ..._buildFields(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_EditResult(_buildAction())),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  List<Widget> _buildFields() => switch (_kind) {
        _Kind.none => const [],
        _Kind.shortcut => [
            DropdownButton<SystemShortcut>(
              isExpanded: true,
              value: _shortcut,
              dropdownColor: const Color(0xFF1C1C1E),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                for (final shortcut in SystemShortcut.values)
                  DropdownMenuItem(value: shortcut, child: Text(shortcut.label)),
              ],
              onChanged: (shortcut) => setState(() => _shortcut = shortcut ?? _shortcut),
            ),
          ],
        _Kind.openApp => [
            _DialogTextField(controller: _appPathController, hint: '/Applications/Safari.app'),
          ],
        _Kind.runCommand => [
            _DialogTextField(controller: _commandController, hint: '/usr/bin/say'),
            const SizedBox(height: 8),
            _DialogTextField(controller: _argsController, hint: 'Arguments (space-separated)'),
          ],
      };
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          isDense: true,
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
        ),
      );
}
