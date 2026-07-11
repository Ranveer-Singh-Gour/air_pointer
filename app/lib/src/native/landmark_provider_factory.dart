import 'dart:io';

import 'package:air_pointer/air_pointer.dart';

import 'vision_landmark_provider.dart';
import 'windows_landmark_provider.dart';

/// Picks the [LandmarkProvider] for the current OS — the one seam where
/// this app's cross-platform support is genuinely uneven: macOS gets real
/// Vision-framework hand tracking, Windows gets [WindowsLandmarkProvider],
/// a stub that never detects a hand (see its doc comment for why).
LandmarkProvider createLandmarkProvider() {
  if (Platform.isMacOS) return VisionLandmarkProvider();
  if (Platform.isWindows) return WindowsLandmarkProvider();
  throw UnsupportedError(
    'No LandmarkProvider for ${Platform.operatingSystem} — air_pointer_app '
    'currently ships macOS and Windows-scaffold support only.',
  );
}
