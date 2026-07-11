import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

import '../calibration/calibration_screen.dart';
import '../native/camera_permission.dart';
import '../native/vision_landmark_provider.dart';

/// Stage 2 verification screen — NOT part of the shipping app.
///
/// Wires `VisionLandmarkProvider` into an unmodified `GestureInputSource`
/// (MediaPipe-tuned defaults) and shows live [GestureDebugInfo] so pinch
/// detection and the calibration flow can be watched end-to-end against
/// real Vision data, per the plan's Stage 2. In particular this is where
/// `GestureCalibrator`'s hard sample-acceptance gates either work or hang —
/// if the "hold open"/"hold pinch" progress bars never fill, that's the
/// signal Vision's pinch-distance scale needs recalibrating against
/// `GestureCalibrator.openMinDist`/`closeMaxDist`.
class GestureDebugScreen extends StatefulWidget {
  const GestureDebugScreen({super.key});

  @override
  State<GestureDebugScreen> createState() => _GestureDebugScreenState();
}

class _GestureDebugScreenState extends State<GestureDebugScreen> {
  GestureInputSource? _source;
  GestureDebugInfo? _info;
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

    final source = GestureInputSource(
      landmarkProvider: VisionLandmarkProvider(),
      scrollEnabled: true,
      onError: (e, st) {
        if (mounted) setState(() => _status = 'error: $e');
      },
    );
    // Placeholder size — real screen-pixel mapping is Stage 4's concern
    // (CGDisplayBounds). This only needs to be non-zero for the recognizer's
    // deadzone/dwell-radius math, which isn't under test here.
    source.updateCanvasSize(const Size(1280, 800));
    source.debugInfo.listen((info) {
      if (mounted) setState(() => _info = info);
    });
    await source.initialize();
    if (!mounted) return;
    setState(() {
      _source = source;
      _status = 'tracking';
    });
  }

  @override
  void dispose() {
    _source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final info = _info;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (source != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: source.buildCameraPreview(width: 336, height: 189),
                  ),
                const SizedBox(height: 20),
                if (source == null)
                  Text(_status, style: const TextStyle(color: Colors.white70))
                else if (info == null)
                  const Text('waiting for first frame…', style: TextStyle(color: Colors.white70))
                else
                  _DebugInfoPanel(info: info),
                const SizedBox(height: 24),
                if (source != null)
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => CalibrationDialog(source: source),
                    ),
                    child: const Text('Calibrate'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugInfoPanel extends StatelessWidget {
  const _DebugInfoPanel({required this.info});

  final GestureDebugInfo info;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('phase', info.phase.name),
            _row('pinchDistance', info.pinchDistance.toStringAsFixed(4)),
            _row('dwellProgress', info.dwellProgress.toStringAsFixed(2)),
            _row('isPointing', info.isPointing.toString()),
            _row('handedness', info.handedness.name),
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      );
}
