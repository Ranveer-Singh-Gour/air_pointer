import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Held here (not just locally) so the capture session and its delegate
  // outlive this method — ARC would tear them down otherwise.
  private var handTracker: CameraHandTracker?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let landmarkEventChannel = HandLandmarkEventChannel()
    FlutterEventChannel(
      name: HandLandmarkEventChannel.channelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setStreamHandler(landmarkEventChannel)

    let tracker = CameraHandTracker(eventChannel: landmarkEventChannel)
    landmarkEventChannel.handTracker = tracker
    handTracker = tracker

    flutterViewController.registrar(forPlugin: "CameraPreview").register(
      CameraPreviewViewFactory(handTracker: tracker),
      withId: CameraPreviewViewFactory.viewType
    )

    PermissionsChannel.register(on: flutterViewController.registrar(forPlugin: "Permissions"))

    super.awakeFromNib()
  }
}
