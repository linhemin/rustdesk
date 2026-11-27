import UIKit
import Flutter
import AVFoundation
import Network

@_cdecl("rustdesk_ios_activate_remote_audio")
func rustdeskIosActivateRemoteAudio() -> Int32 {
  do {
    try AVAudioSession.sharedInstance().setActive(true)
    return 0
  } catch {
    return Int32(clamping: (error as NSError).code)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let diagnosticPath = NWPathMonitor()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let build = UInt32(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    rustdesk_ios_diagnostic_path(0, build)
    diagnosticPath.pathUpdateHandler = { path in
      // This describes the OS default path. ICE sockets can choose a different interface.
      let kind: UInt8
      if path.status != .satisfied { kind = 0 }
      else if path.usesInterfaceType(.wifi) { kind = 1 }
      else if path.usesInterfaceType(.cellular) { kind = 2 }
      else { kind = 3 }
      rustdesk_ios_diagnostic_path(kind, build)
      if path.status == .satisfied {
        rustdesk_ios_p2p_wake()
      }
    }
    diagnosticPath.start(queue: DispatchQueue(label: "com.rustdesk.diagnostic-path"))
    do {
      // Mix remote audio with other apps while still respecting silent mode.
      try AVAudioSession.sharedInstance().setCategory(.ambient)
    } catch {
      NSLog("Failed to configure audio mixing: %@", error.localizedDescription)
    }
    dummyMethodToEnforceBundling();
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // With the UIScene life cycle, the FlutterViewController only exists once the scene
  // connects, and FlutterAppDelegate reaches its engine through `window`. A launch URL
  // also arrives with the scene instead of in launchOptions, so forward it to plugins here.
  func sceneWillConnect(window: UIWindow?, launchURL: URL?) {
    self.window = window
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "PhoneMicrophone") {
      let channel = FlutterMethodChannel(name: "rustdesk/phone-microphone", binaryMessenger: registrar.messenger())
      var previousAudio: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
      channel.setMethodCallHandler { call, result in
        let session = AVAudioSession.sharedInstance()
        switch call.method {
        case "prepare":
          session.requestRecordPermission { granted in
            DispatchQueue.main.async {
              guard granted, UIApplication.shared.applicationState == .active else { result(false); return }
              do {
                previousAudio = (session.category, session.mode, session.categoryOptions)
                try session.setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])
                try session.setActive(true)
                result(true)
              } catch {
                result(FlutterError(code: "microphone", message: error.localizedDescription, details: nil))
              }
            }
          }
        case "output-status":
          let ports = session.currentRoute.outputs.map { $0.portType.rawValue }
          result("route=\(ports.joined(separator: ",")) volume=\(session.outputVolume) category=\(session.category.rawValue)")
        case "stop":
          do {
            let keepPlayback = call.arguments as? Bool ?? false
            if !keepPlayback {
              try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            if let previous = previousAudio {
              try session.setCategory(previous.0, mode: previous.1, options: previous.2)
              previousAudio = nil
            }
            result(nil)
          } catch {
            result(FlutterError(code: "microphone", message: error.localizedDescription, details: nil))
          }
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    if let registrar = registrar(forPlugin: "AppleWorkspaceNavigation") {
      AppleWorkspaceNavigationFactory.register(with: registrar)
    }
    var launchOptions: [UIApplication.LaunchOptionsKey: Any] = [:]
    if let launchURL = launchURL {
      launchOptions[.url] = launchURL
    }
    _ = super.application(UIApplication.shared, didFinishLaunchingWithOptions: launchOptions)
    DispatchQueue.main.async {
      AwesunSessionOverlay.shared.installIfNeeded(window: window)
    }
  }
    
  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }
}
