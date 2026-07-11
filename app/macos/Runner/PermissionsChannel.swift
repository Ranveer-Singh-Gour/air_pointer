import AVFoundation
import Cocoa
import FlutterMacOS

/// One-off, non-hot-path native calls: camera authorization status/request,
/// and an Accessibility-settings deep link. Backs
/// `MethodChannel("air_pointer_app/permissions")`.
///
/// Accessibility-trust *checking* itself is done Dart-side via FFI (see
/// `system_cursor_ffi.dart`, Stage 3) so it shares one binding module with
/// the cursor-injection code — this channel only owns the "open System
/// Settings" deep link, which is AppKit-only.
final class PermissionsChannel: NSObject {
  static let channelName = "air_pointer_app/permissions"

  static func register(on registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
    let instance = PermissionsChannel()
    channel.setMethodCallHandler(instance.handle)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cameraAuthorizationStatus":
      result(Self.statusString(AVCaptureDevice.authorizationStatus(for: .video)))

    case "requestCameraAccess":
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }

    case "openAccessibilitySettings":
      let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
      NSWorkspace.shared.open(url)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func statusString(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "notDetermined"
    }
  }
}
