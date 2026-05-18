import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller: FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.aegis.health/litert", binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "loadModels":
        // In a real macOS implementation, we'd load the C++ MediaPipe/LiteRT libraries
        // For now, we stub to allow the app to launch and UI to show.
        result(true)
      case "generate":
        let prompt = call.arguments as? [String: Any]
        let system = prompt?["system"] as? String ?? ""
        result("Aegis macOS: On-device inference requires MediaPipe C++ SDK linking. System: \(system)")
      case "embed":
        result([0.1, 0.2, 0.3]) // Stub embedding
      case "extract":
        result("{\"intent\": \"INGEST\", \"symptom\": \"headache\"}") // Stub extraction
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    super.applicationDidFinishLaunching(notification)
  }
}
