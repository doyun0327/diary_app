import AppTrackingTransparency
import Flutter
import Photos
import Security
import UIKit
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DiaryFilesPlugin") {
      DiaryFilesPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InviteLinkSceneForwarder") {
      InviteLinkSceneForwarder.register(with: registrar)
    }
  }
}

/// 초대 링크(`pageby://join?code=…`, `https://pageby.stream/join…`)를 `app_links` 로 넘긴다.
/// 이 앱은 UIScene(SceneDelegate) 구조라 iOS 가 링크를 scene 으로만 보내는데,
/// app_links 6.4.1 은 AppDelegate 콜백만 받아서 링크가 Dart 까지 오지 않았음.
/// false 를 돌려줘 Google 로그인 등 다른 플러그인도 같은 링크를 계속 받게 한다.
final class InviteLinkSceneForwarder: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.addSceneDelegate(InviteLinkSceneForwarder())
  }

  // 앱이 꺼져 있다가 링크로 실행될 때
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let options = connectionOptions else { return false }
    options.urlContexts.forEach { AppLinks.shared.handleLink(url: $0.url) }
    options.userActivities
      .compactMap { $0.webpageURL }
      .forEach { AppLinks.shared.handleLink(url: $0) }
    return false
  }

  // 커스텀 스킴 (pageby://)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    URLContexts.forEach { AppLinks.shared.handleLink(url: $0.url) }
    return false
  }

  // Universal Links (https://pageby.stream/…)
  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    if let url = userActivity.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }
    return false
  }
}

/// 설치 무료 AI 용 기기 키 (Keychain). 앱 삭제 후에도 유지되는 경우가 많음.
enum InstallDeviceKeyStore {
  static let shared = InstallDeviceKeyStoreImpl()
}

final class InstallDeviceKeyStoreImpl {
  private let service = "stream.pageby.installDeviceKey"
  private let account = "install-device-key-v1"

  func deviceKey() -> String {
    if let existing = read(), !existing.isEmpty {
      return "i:\(existing)"
    }
    let created = UUID().uuidString.lowercased()
    _ = save(created)
    return "i:\(created)"
  }

  private func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  private func save(_ value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    SecItemDelete([
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ] as CFDictionary)
    let status = SecItemAdd([
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ] as CFDictionary, nil)
    return status == errSecSuccess
  }
}

/// Android `MainActivity` 의 `diary/files` 채널 iOS 버전.
/// - `openSavedFile`: PDF 등 Documents 파일 미리보기
/// - `saveImageToPhotos`: 이미지를 사진 앱(앨범)에 바로 저장
/// - `requestTrackingAuthorization`: ATT 추적 권한 요청 (광고 초기화 전)
/// (`saveToDownloads`, `pickGalleryImage` 는 notImplemented → Dart 쪽 폴백 사용)
final class DiaryFilesPlugin: NSObject, FlutterPlugin, UIDocumentInteractionControllerDelegate {
  /// 미리보기가 떠 있는 동안 해제되지 않도록 강하게 붙잡아 둔다.
  private var documentController: UIDocumentInteractionController?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "diary/files", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DiaryFilesPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openSavedFile":
      guard
        let args = call.arguments as? [String: Any],
        let location = args["uri"] as? String,
        !location.isEmpty
      else {
        result(FlutterError(code: "BAD_ARGS", message: "uri required", details: nil))
        return
      }
      openSavedFile(location, result: result)
    case "saveImageToPhotos":
      guard
        let args = call.arguments as? [String: Any],
        let bytes = args["bytes"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "BAD_ARGS", message: "bytes required", details: nil))
        return
      }
      saveImageToPhotos(bytes.data, result: result)
    case "requestTrackingAuthorization":
      requestTrackingAuthorization(result: result)
    case "getInstallDeviceKey":
      // Keychain UUID — 삭제 후에도 남는 경우가 많아 재설치 무료 복구 완화
      result(InstallDeviceKeyStore.shared.deviceKey())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 사진 앱에 저장 (추가 전용 권한 = NSPhotoLibraryAddUsageDescription)
  private func saveImageToPhotos(_ data: Data, result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "DENIED", message: "photo add permission denied", details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
      }) { success, error in
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            result(FlutterError(
              code: "SAVE_FAILED",
              message: error?.localizedDescription ?? "save failed",
              details: nil))
          }
        }
      }
    }
  }

  /// ATT 팝업은 앱이 active 상태일 때만 뜬다. 아직 아니면 active 가 될 때까지 기다림.
  /// 결과: 0 notDetermined, 1 restricted, 2 denied, 3 authorized
  private func requestTrackingAuthorization(result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result(3)
      return
    }
    if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
      result(Int(ATTrackingManager.trackingAuthorizationStatus.rawValue))
      return
    }
    let request = {
      ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async { result(Int(status.rawValue)) }
      }
    }
    if UIApplication.shared.applicationState == .active {
      request()
      return
    }
    var token: NSObjectProtocol?
    token = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      if let token { NotificationCenter.default.removeObserver(token) }
      request()
    }
  }

  private func openSavedFile(_ location: String, result: @escaping FlutterResult) {
    let url = location.hasPrefix("file:") ? URL(string: location) : URL(fileURLWithPath: location)
    guard let url, FileManager.default.fileExists(atPath: url.path) else {
      result(FlutterError(code: "OPEN_FAILED", message: "file not found", details: location))
      return
    }

    let controller = UIDocumentInteractionController(url: url)
    controller.delegate = self
    documentController = controller

    // 미리보기를 지원하지 않는 형식이면 "다른 앱으로 열기" 메뉴로 대체
    if controller.presentPreview(animated: true) {
      result(true)
      return
    }
    guard let view = Self.topViewController()?.view,
          controller.presentOptionsMenu(from: view.bounds, in: view, animated: true)
    else {
      documentController = nil
      result(FlutterError(code: "OPEN_FAILED", message: "no app can open this file", details: nil))
      return
    }
    result(true)
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    Self.topViewController() ?? UIViewController()
  }

  func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
    documentController = nil
  }

  func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
    documentController = nil
  }

  /// 알림 탭으로 실행될 때는 씬이 아직 foregroundActive 가 아닐 수 있어 첫 씬으로 폴백
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
