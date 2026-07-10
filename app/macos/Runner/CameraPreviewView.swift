import AVFoundation
import Cocoa
import FlutterMacOS

/// Wraps `CameraHandTracker.previewLayer` in an `NSView` for embedding into
/// Flutter via `AppKitView` (Dart side: `vision_landmark_provider.dart`'s
/// `buildPreview()`). Renders natively — the preview layer already exists on
/// the shared capture session, this view just gives Flutter something to
/// host, with no per-frame data crossing the Dart/Swift boundary.
final class CameraPreviewView: NSView {
  private let previewLayer: AVCaptureVideoPreviewLayer

  init(frame: CGRect, previewLayer: AVCaptureVideoPreviewLayer) {
    self.previewLayer = previewLayer
    super.init(frame: frame)
    wantsLayer = true
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = bounds
    layer?.addSublayer(previewLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    previewLayer.frame = bounds
  }
}

final class CameraPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "air_pointer_app/camera_preview"

  private let handTracker: CameraHandTracker

  init(handTracker: CameraHandTracker) {
    self.handTracker = handTracker
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    return CameraPreviewView(frame: .zero, previewLayer: handTracker.previewLayer)
  }
}
