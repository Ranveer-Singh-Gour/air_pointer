import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

import '../native/camera_permission.dart';
import '../native/vision_landmark_provider.dart';

/// Stage 1 throwaway verification screen — NOT part of the shipping app.
///
/// Draws the 21 raw Vision joints live over the camera preview so the two
/// open questions in `CameraHandTracker.swift` (`flipX`/`flipY`) can be
/// settled empirically against a real hand, per the plan's Stage 1:
/// - Raise your hand -> do the dots move up?
/// - Move your hand to your own right -> do the dots move right?
/// If either answer is "no," flip the corresponding constant in
/// `CameraHandTracker.swift` and rebuild.
class HandDebugScreen extends StatefulWidget {
  const HandDebugScreen({super.key});

  @override
  State<HandDebugScreen> createState() => _HandDebugScreenState();
}

class _HandDebugScreenState extends State<HandDebugScreen> {
  VisionLandmarkProvider? _provider;
  HandDetectionFrame _latest = const HandDetectionFrame();
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

    final provider = VisionLandmarkProvider();
    provider.frames.listen((frame) {
      if (mounted) setState(() => _latest = frame);
    });
    setState(() {
      _provider = provider;
      _status = 'tracking';
    });
  }

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_provider != null) _provider!.buildPreview(),
          CustomPaint(painter: _HandOverlayPainter(_latest)),
          Positioned(
            left: 16,
            top: 16,
            right: 16,
            child: Text(
              _status == 'tracking'
                  ? 'Raise hand: dots should move up.\n'
                      'Move hand to your right: dots should move right.\n'
                      'hands detected: ${_handCount(_latest)}'
                  : _status,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  int _handCount(HandDetectionFrame f) =>
      (f.landmarks.isNotEmpty ? 1 : 0) + (f.secondHandLandmarks.isNotEmpty ? 1 : 0);
}

class _HandOverlayPainter extends CustomPainter {
  _HandOverlayPainter(this.frame);

  final HandDetectionFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    _paintHand(canvas, size, frame.landmarks, const Color(0xFF00E5A0));
    _paintHand(canvas, size, frame.secondHandLandmarks, const Color(0xFFFFC400));
  }

  void _paintHand(Canvas canvas, Size size, List<HandLandmarkPoint> lms, Color color) {
    if (lms.length < 21) return;
    final dotPaint = Paint()..color = color;
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2;

    Offset toOffset(HandLandmarkPoint p) => Offset(p.x * size.width, p.y * size.height);

    for (final connection in handLandmarkConnections) {
      canvas.drawLine(
        toOffset(lms.getLandmark(connection[0])),
        toOffset(lms.getLandmark(connection[1])),
        linePaint,
      );
    }
    for (final p in lms) {
      canvas.drawCircle(toOffset(p), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandOverlayPainter oldDelegate) => oldDelegate.frame != frame;
}
