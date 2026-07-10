import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

import '../calibration/calibration_screen.dart';
import '../cursor/gesture_session_controller.dart';
import '../native/camera_permission.dart';

/// Stage 4 verification screen — NOT part of the shipping app.
///
/// Combines the Stage 1/2-validated `VisionLandmarkProvider` with the
/// Stage 3-validated `SystemCursorSink` via `GestureSessionController`.
/// Tracking (camera + `debugInfo`) and cursor control are separate
/// switches on purpose: tracking can run, and calibration can be checked
/// via `debugInfo`, before the real cursor is ever touched — cursor
/// control defaults OFF and requires an explicit tap.
///
/// Per the plan's Stage 4 verification: moving a real hand should move the
/// real system cursor in a different, already-open app; pinch should
/// click/drag; two-finger scroll should scroll a real window.
class LiveControlDebugScreen extends StatefulWidget {
  const LiveControlDebugScreen({super.key});

  @override
  State<LiveControlDebugScreen> createState() => _LiveControlDebugScreenState();
}

class _LiveControlDebugScreenState extends State<LiveControlDebugScreen> {
  GestureSessionController? _controller;
  GestureDebugInfo? _info;
  bool _cursorControlEnabled = false;
  String _status = 'checking camera permission…';

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    var status = await CameraPermission.status();
    if (status == 'notDetermined') {
      final granted = await CameraPermission.request();
      status = granted ? 'authorized' : 'denied';
    }
    if (!mounted) return;
    if (status != 'authorized') {
      setState(() => _status = 'Camera access $status — enable it in System Settings > Privacy & Security > Camera.');
      return;
    }

    final controller = GestureSessionController(
      onError: (e, st) {
        if (mounted) setState(() => _status = 'error: $e');
      },
    );
    controller.source.debugInfo.listen((info) {
      if (mounted) setState(() => _info = info);
    });
    await controller.start();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _status = 'tracking';
    });
  }

  void _toggleCursorControl(bool enabled) {
    _controller?.setCursorControlEnabled(enabled);
    setState(() => _cursorControlEnabled = enabled);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final info = _info;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: controller.source.buildCameraPreview(width: 336, height: 189),
                  ),
                const SizedBox(height: 16),
                if (controller == null)
                  Text(_status, style: const TextStyle(color: Colors.white70))
                else if (info != null)
                  Text(
                    'phase: ${info.phase.name}   pinch: ${info.pinchDistance.toStringAsFixed(3)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                const SizedBox(height: 16),
                if (controller != null) ...[
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => CalibrationDialog(source: controller.source),
                    ),
                    child: const Text('Calibrate first'),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (_cursorControlEnabled ? Colors.redAccent : Colors.white).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _cursorControlEnabled ? Colors.redAccent : Colors.white24),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _cursorControlEnabled
                              ? '⚠ Cursor control is ON — your hand now drives the real system cursor.'
                              : 'Cursor control is off. Tracking-only — the real cursor is untouched.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _cursorControlEnabled ? Colors.redAccent : Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _cursorControlEnabled ? Colors.redAccent : null,
                          ),
                          onPressed: () => _toggleCursorControl(!_cursorControlEnabled),
                          child: Text(_cursorControlEnabled ? 'Disable cursor control' : 'Enable cursor control'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
