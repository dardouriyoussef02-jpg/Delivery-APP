import Flutter
import MapKit
import UIKit

/// Native iOS entry point for the same `delivery.driver/native` channel used by
/// `MainActivity.kt` on Android:
///
///  - `openNavigation`: hands the stop to Apple Maps in driving mode.
///  - `shareText`: presents the share sheet (Messages, WhatsApp, Mail, ...).
///
/// Dart falls back to `url_launcher` whenever a method is unavailable, so the
/// app keeps working even if this channel is not reachable.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeChannel: FlutterMethodChannel?
  private var channelReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // With the scene-based lifecycle the root view controller only exists a
    // moment after launch, so we resolve it on the next run-loop turns.
    registerNativeChannel(attempt: 0)

    return launched
  }

  // MARK: - Channel wiring

  private func registerNativeChannel(attempt: Int) {
    guard !channelReady else { return }

    guard let messenger = rootBinaryMessenger() else {
      if attempt < 8 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          self?.registerNativeChannel(attempt: attempt + 1)
        }
      }
      return
    }

    let channel = FlutterMethodChannel(name: "delivery.driver/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    nativeChannel = channel
    channelReady = true
  }

  private func rootBinaryMessenger() -> FlutterBinaryMessenger? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller.binaryMessenger
    }

    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for sceneWindow in windowScene.windows {
        if let controller = sceneWindow.rootViewController as? FlutterViewController {
          return controller.binaryMessenger
        }
      }
    }
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(true)

    case "openNavigation":
      guard
        let args = call.arguments as? [String: Any],
        let lat = args["lat"] as? Double,
        let lng = args["lng"] as? Double
      else {
        result(FlutterError(code: "BAD_ARGS", message: "lat/lng are required", details: nil))
        return
      }
      let label = (args["label"] as? String) ?? "Destination"
      result(openNavigation(latitude: lat, longitude: lng, label: label))

    case "shareText":
      guard
        let args = call.arguments as? [String: Any],
        let text = args["text"] as? String,
        !text.isEmpty
      else {
        result(FlutterError(code: "BAD_ARGS", message: "text is required", details: nil))
        return
      }
      result(share(text: text))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Actions

  private func openNavigation(latitude: Double, longitude: Double, label: String) -> Bool {
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    guard CLLocationCoordinate2DIsValid(coordinate) else { return false }

    let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    destination.name = label
    destination.openInMaps(
      launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
    )
    return true
  }

  private func share(text: String) -> Bool {
    guard let top = topViewController() else { return false }

    let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    activity.popoverPresentationController?.sourceView = top.view
    activity.popoverPresentationController?.sourceRect = CGRect(
      x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
    )

    top.present(activity, animated: true)
    return true
  }

  private func topViewController() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      guard var current = windowScene.windows.first?.rootViewController else { continue }
      while let presented = current.presentedViewController {
        current = presented
      }
      return current
    }
    return nil
  }
}
