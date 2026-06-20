/// Lifecycle states emitted by [GestureInputSource.statusStream].
///
/// Transitions (web):
///   initializing → cameraReady → tracking ⇄ lost
///                                         ↘ error (terminal)
///
/// Transitions (native, with [LandmarkProvider]):
///   initializing → cameraReady (on first frame) → tracking ⇄ lost
///                                                           ↘ error (terminal)
///
/// On native with no [LandmarkProvider], the stream emits nothing.
sealed class HandTrackingStatus {
  const HandTrackingStatus();
}

/// [GestureInputSource.initialize] was called; camera and model are loading.
final class HandTrackingInitializing extends HandTrackingStatus {
  const HandTrackingInitializing();
}

/// Camera is live and the hand-detection model is ready; scanning for hands.
///
/// On web this fires when the MediaPipe worker posts `ready`.
/// On native it fires when the [LandmarkProvider] delivers its first frame.
final class HandTrackingCameraReady extends HandTrackingStatus {
  const HandTrackingCameraReady();
}

/// At least one hand has been confirmed in frame.
final class HandTrackingTracking extends HandTrackingStatus {
  const HandTrackingTracking();
}

/// A previously tracked hand has left the frame.
///
/// Re-emits [HandTrackingTracking] if the hand returns.
final class HandTrackingLost extends HandTrackingStatus {
  const HandTrackingLost();
}

/// An unrecoverable error occurred (camera denied, model load failed, etc.).
///
/// No further [HandTrackingTracking] or [HandTrackingLost] events are emitted
/// after this state.
final class HandTrackingError extends HandTrackingStatus {
  const HandTrackingError(this.error);

  final Object error;
}
