import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

import '../cursor/system_cursor_sink.dart';
import '../native/accessibility_permission.dart';
import '../native/macos_cursor_backend.dart';

/// Stage 3 verification screen — NOT part of the shipping app. macOS-only,
/// same as the pipeline it exercises (`MacosCursorBackend` directly, not
/// the cross-platform `CursorBackend` interface — this is a debug tool for
/// the CGEvent injection specifically, not a general-purpose one).
///
/// Exercises `MacosCursorBackend`/`SystemCursorSink` independently of the
/// gesture pipeline, per the plan's Stage 3:
/// - Corner buttons resolve the coordinate-origin question empirically
///   (does `moveTo` land where expected, not just where CGRect math says).
/// - The trust indicator confirms `CGEventPost` is gated correctly.
/// - "Run scripted drag" feeds a fake Down/Move/Up sequence straight into
///   `SystemCursorSink`, bypassing hand tracking entirely, so a real
///   OS-level drag (e.g. of a Finder icon) can be observed.
class CursorInjectionDebugScreen extends StatefulWidget {
  const CursorInjectionDebugScreen({super.key});

  @override
  State<CursorInjectionDebugScreen> createState() => _CursorInjectionDebugScreenState();
}

class _CursorInjectionDebugScreenState extends State<CursorInjectionDebugScreen> {
  final _ffi = MacosCursorBackend();
  final _fakeEvents = StreamController<PointerInputEvent>.broadcast();
  late final _sink = SystemCursorSink(_fakeEvents.stream);

  @override
  void dispose() {
    _sink.dispose();
    unawaited(_fakeEvents.close());
    super.dispose();
  }

  Rect get _bounds => _ffi.mainDisplayBounds;

  void _moveToCorner(Alignment alignment) {
    final b = _bounds;
    final dx = alignment.x <= 0 ? b.left : b.right - 1;
    final dy = alignment.y <= 0 ? b.top : b.bottom - 1;
    _ffi.moveTo(Offset(dx, dy));
  }

  Future<void> _runScriptedDrag() async {
    final b = _bounds;
    final start = Offset(b.center.dx, b.center.dy);
    _fakeEvents.add(CanvasDownEvent(position: start));
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 12));
      _fakeEvents.add(CanvasMoveEvent(position: start + Offset(i * 5.0, 0)));
    }
    await Future<void>.delayed(const Duration(milliseconds: 12));
    _fakeEvents.add(CanvasUpEvent(position: start + const Offset(100, 0)));
  }

  Future<void> _runScriptedScroll() async {
    final b = _bounds;
    final center = Offset(b.center.dx, b.center.dy);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      _fakeEvents.add(CanvasScrollEvent(position: center, delta: const Offset(0, 20)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trusted = _ffi.isTrusted;
    final bounds = _bounds;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accessibility trusted: $trusted',
                  style: TextStyle(color: trusted ? Colors.greenAccent : Colors.redAccent, fontSize: 15),
                ),
                Text(
                  'Main display bounds: ${bounds.width.toInt()}x${bounds.height.toInt()} '
                  'at (${bounds.left.toInt()}, ${bounds.top.toInt()})',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (!trusted)
                  OutlinedButton(
                    onPressed: () async {
                      await AccessibilityPermission.openSystemSettings();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Open Accessibility settings'),
                  ),
                const SizedBox(height: 20),
                const Text('Coordinate-origin test', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _btn('Top-left', () => _moveToCorner(Alignment.topLeft)),
                    _btn('Top-right', () => _moveToCorner(Alignment.topRight)),
                    _btn('Bottom-left', () => _moveToCorner(Alignment.bottomLeft)),
                    _btn('Bottom-right', () => _moveToCorner(Alignment.bottomRight)),
                    _btn('Center', () => _moveToCorner(Alignment.center)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Click/drag/scroll test', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const Text(
                  'Position a Finder icon under the screen center before running.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _btn('Run scripted drag (center, +100px right)', _runScriptedDrag),
                    _btn('Run scripted scroll (center)', _runScriptedScroll),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onPressed) =>
      FilledButton(onPressed: onPressed, child: Text(label));
}
