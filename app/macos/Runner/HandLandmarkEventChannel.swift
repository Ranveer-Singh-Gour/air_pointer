import Cocoa
import FlutterMacOS

/// Bridges `CameraHandTracker`'s per-frame hand-landmark output to Dart as a
/// continuous push stream, backing `EventChannel("air_pointer_app/hand_landmarks")`.
///
/// One long-lived sink, no per-frame call/response round trip — the right
/// shape for a ~30fps stream, and it maps directly onto `LandmarkProvider.frames`
/// on the Dart side, which is itself required to be a broadcast `Stream`.
final class HandLandmarkEventChannel: NSObject, FlutterStreamHandler {
  static let channelName = "air_pointer_app/hand_landmarks"

  private var eventSink: FlutterEventSink?

  /// Set once `CameraHandTracker` exists (construction order: this channel
  /// is created first since the tracker needs a reference to it). Camera
  /// lifecycle is tied directly to whether Dart's `LandmarkProvider.frames`
  /// stream has a subscriber — `onListen`/`onCancel` fire exactly when Dart
  /// subscribes/cancels, so no separate start/stop channel is needed.
  weak var handTracker: CameraHandTracker?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    handTracker?.start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    handTracker?.stop()
    return nil
  }

  /// Sends one frame's worth of hand data to Dart. Must be called on the
  /// main thread — `FlutterEventSink` is not thread-safe.
  ///
  /// `hands` is a list of hands, each a list of 21 `{x, y}` dicts in
  /// `HandLandmarkType` order (see `CameraHandTracker.landmarkOrder`), with
  /// `x`/`y` normalized to [0, 1]. An empty list means no hand detected this
  /// frame — still sent, so the Dart-side recognizer's grace/lost windowing
  /// (which expects one frame per inference step, hand or not) keeps working.
  func send(hands: [[[String: Double]]]) {
    eventSink?(["hands": hands])
  }
}
