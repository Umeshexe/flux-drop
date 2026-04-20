import Flutter
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerStorageChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerStorageChannel() {
    guard let registrar = registrar(forPlugin: "FluxDropStorageChannel") else {
      return
    }

    let storageChannel = FlutterMethodChannel(
      name: "fluxdrop/storage",
      binaryMessenger: registrar.messenger()
    )

    storageChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getFreeSpace":
        do {
          let attrs = try FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
          )
          let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
          result(free)
        } catch {
          result(
            FlutterError(
              code: "UNAVAILABLE",
              message: "Free space unavailable",
              details: nil
            )
          )
        }

      case "saveToGallery":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(
            FlutterError(
              code: "INVALID_ARGS",
              message: "path argument is required",
              details: nil
            )
          )
          return
        }
        let fileURL = URL(fileURLWithPath: path)
        let ext = fileURL.pathExtension.lowercased()
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "webm", "3gp"]
        let isVideo = videoExts.contains(ext)

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          guard status == .authorized || status == .limited else {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "PERMISSION_DENIED",
                  message: "Photos permission denied",
                  details: nil
                )
              )
            }
            return
          }

          PHPhotoLibrary.shared().performChanges({
            if isVideo {
              PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
              PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
          }) { success, error in
            DispatchQueue.main.async {
              if success {
                result("saved")
              } else {
                result(
                  FlutterError(
                    code: "SAVE_FAILED",
                    message: error?.localizedDescription ?? "Unknown error",
                    details: nil
                  )
                )
              }
            }
          }
      }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
