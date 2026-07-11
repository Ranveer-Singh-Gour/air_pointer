import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

/// No-op [LandmarkProvider] for Windows — mirrors the root `air_pointer`
/// package's own documented pattern for
/// `lib/src/gesture/gesture_input_source_native.dart`: "no-op stub;
/// consumers wire their own `LandmarkProvider`."
///
/// Windows has no OS-bundled hand-pose API equivalent to macOS's Vision
/// framework (`VNDetectHumanHandPoseRequest`), and there's no Windows
/// machine in this project's development environment to build or verify a
/// real backend against. [frames] never emits a detected hand, so the app
/// runs (tray, onboarding, settings, cursor injection all work) but
/// tracking never starts — this is the extension point a real Windows
/// hand-tracking backend plugs into.
///
/// The most credible path to a real implementation would reuse the
/// `air_pointer` web platform's already-shipped MediaPipe Tasks Vision
/// WASM bundle, hosted in an embedded WebView (`webview_windows` or
/// similar) fed by Windows camera capture, with landmarks bridged back via
/// a JS-to-Dart channel — the landmark *detection* logic would then be
/// identical to the tested web backend; only the camera-capture and
/// message-bridging glue would be new. That's a substantial, standalone
/// piece of work, intentionally not attempted here.
class WindowsLandmarkProvider implements LandmarkProvider {
  final _controller = StreamController<HandDetectionFrame>.broadcast();

  @override
  Stream<HandDetectionFrame> get frames => _controller.stream;

  @override
  Widget buildPreview({double? width, double? height}) => SizedBox(
        width: width,
        height: height,
        child: const ColoredBox(
          color: Color(0xFF1C1C1E),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hand-tracking backend on Windows yet — see '
                'WindowsLandmarkProvider.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    unawaited(_controller.close());
  }
}
