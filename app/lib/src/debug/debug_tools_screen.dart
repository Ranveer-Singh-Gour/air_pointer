import 'package:flutter/material.dart';

import 'cursor_injection_debug_screen.dart';
import 'gesture_debug_screen.dart';
import 'hand_debug_screen.dart';
import 'live_control_debug_screen.dart';

/// Tabbed access to the build-plan's Stage 1-4 verification screens —
/// reachable from the tray's "Debug tools…" item for ongoing
/// troubleshooting (e.g. re-diagnosing the Y-flip/mirror mapping), not
/// part of the primary user-facing flow.
class DebugToolsScreen extends StatefulWidget {
  const DebugToolsScreen({super.key});

  @override
  State<DebugToolsScreen> createState() => _DebugToolsScreenState();
}

enum _Stage { rawJoints, gestureDebug, cursorInjection, liveControl }

class _DebugToolsScreenState extends State<DebugToolsScreen> {
  _Stage _stage = _Stage.liveControl;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          switch (_stage) {
            _Stage.rawJoints => const HandDebugScreen(),
            _Stage.gestureDebug => const GestureDebugScreen(),
            _Stage.cursorInjection => const CursorInjectionDebugScreen(),
            _Stage.liveControl => const LiveControlDebugScreen(),
          },
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Row(
              children: [
                for (final s in _Stage.values)
                  TextButton(
                    onPressed: () => setState(() => _stage = s),
                    child: Text(s.name, style: TextStyle(fontWeight: s == _stage ? FontWeight.bold : FontWeight.normal)),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ],
      );
}
