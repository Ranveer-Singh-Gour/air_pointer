import AVFoundation
import Cocoa
import Vision

/// Owns the camera capture session and runs Vision's hand-pose detector on
/// every frame, pushing results to Dart via `HandLandmarkEventChannel`.
///
/// Landmark path and preview path are deliberately independent: this class
/// runs `VNDetectHumanHandPoseRequest` on the raw sample buffer, while
/// `previewLayer` (exposed for `CameraPreviewView`) renders natively via
/// `AVCaptureVideoPreviewLayer` with zero Flutter/Vision involvement — no
/// reason to pay per-frame marshalling cost twice.
final class CameraHandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  /// `VNHumanHandPoseObservation.JointName`, in the exact order the Dart
  /// side's `HandLandmarkType` enum expects (`hand_landmark_type.dart`).
  /// Verified 1:1 name mapping against Apple's 21-case joint enum — this is
  /// a rename, not a reconstruction (wrist, 4 joints x 4 digits, "little" =
  /// pinky in Apple's naming).
  private static let landmarkOrder: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
    .indexMCP, .indexPIP, .indexDIP, .indexTip,
    .middleMCP, .middlePIP, .middleDIP, .middleTip,
    .ringMCP, .ringPIP, .ringDIP, .ringTip,
    .littleMCP, .littlePIP, .littleDIP, .littleTip,
  ]

  /// STAGE 1 — VERIFY EMPIRICALLY, DO NOT TRUST THIS DEFAULT.
  ///
  /// Vision's `VNRecognizedPoint.location` is normalized with origin at
  /// bottom-left (y increases upward); this package's landmark convention
  /// (matching MediaPipe, see the drawing example in
  /// `hand_landmark_type.dart`'s doc comment) is top-left origin. Flipping
  /// y here (`y' = 1 - y`) is the documented-convention best guess — confirm
  /// with the debug overlay (hand moves up on screen -> dot moves up) before
  /// trusting it, then delete this comment.
  private static let flipY = true

  /// STAGE 1 — VERIFY EMPIRICALLY, DO NOT TRUST THIS DEFAULT.
  ///
  /// `AVCaptureVideoDataOutput` delivers the raw, unmirrored sensor image.
  /// For a *control* surface (not a selfie preview) it's not obvious
  /// whether "unmirrored" or "mirrored" feels natural — confirm with the
  /// debug overlay (hand moves right from the user's own point of view ->
  /// dot moves right on screen) before trusting it, then delete this comment.
  private static let flipX = true

  /// Below this confidence, Vision still returns a point but it's likely
  /// noise (occluded joint, edge of frame). Reported anyway via `visibility`
  /// rather than dropped — `HandLandmarkPoint.visibility` already exists for
  /// exactly this (mirrors how the web backend forwards MediaPipe's
  /// per-point visibility) and the recognizer can weight low-confidence
  /// points however it sees fit, rather than this layer silently deciding.
  private let handPoseRequest: VNDetectHumanHandPoseRequest = {
    let request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 2
    return request
  }()

  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let processingQueue = DispatchQueue(label: "air_pointer_app.hand_tracking", qos: .userInteractive)
  private let eventChannel: HandLandmarkEventChannel

  private(set) var isRunning = false

  /// Exposed so `CameraPreviewView` can attach a native, Flutter-independent
  /// preview layer to the same capture session.
  let previewLayer: AVCaptureVideoPreviewLayer

  init(eventChannel: HandLandmarkEventChannel) {
    self.eventChannel = eventChannel
    self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    super.init()
    configureSession()
  }

  private func configureSession() {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .medium // 480p is plenty for hand-pose landmarks; keeps inference cheap.

    if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
      ?? AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      captureSession.canAddInput(input) {
      captureSession.addInput(input)
    }

    videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true
    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }

    captureSession.commitConfiguration()
  }

  /// Starts the capture session (camera light on). No-op if already running
  /// or if camera access hasn't been authorized — callers should have
  /// already gone through `PermissionsChannel` before calling this.
  func start() {
    guard !isRunning else { return }
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
    isRunning = true
    processingQueue.async { [captureSession] in
      captureSession.startRunning()
    }
  }

  /// Stops the capture session (camera light off). This is the app's one
  /// real trust signal while "disabled" — see `GestureSessionController`.
  func stop() {
    guard isRunning else { return }
    isRunning = false
    processingQueue.async { [captureSession] in
      captureSession.stopRunning()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
    var hands: [[[String: Double]]] = []
    do {
      try handler.perform([handPoseRequest])
      if let observations = handPoseRequest.results {
        hands = observations.compactMap { Self.landmarks(from: $0) }
      }
    } catch {
      // Non-fatal — skipped frame. Still send an empty-hands frame below so
      // the Dart-side recognizer's grace/lost windowing (which expects one
      // frame per inference step, hand or not) keeps advancing.
    }

    DispatchQueue.main.async { [eventChannel] in
      eventChannel.send(hands: hands)
    }
  }

  private static func landmarks(from observation: VNHumanHandPoseObservation) -> [[String: Double]]? {
    var points: [[String: Double]] = []
    points.reserveCapacity(landmarkOrder.count)
    for joint in landmarkOrder {
      guard let point = try? observation.recognizedPoint(joint) else { return nil }
      let x = flipX ? 1.0 - point.location.x : point.location.x
      let y = flipY ? 1.0 - point.location.y : point.location.y
      points.append(["x": x, "y": y, "visibility": Double(point.confidence)])
    }
    return points
  }
}
