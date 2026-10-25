import Flutter
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

/// Android `MainActivity` 의 `diary/files` 채널 iOS 버전.
/// iOS 는 저장을 Dart 에서 Documents 폴더로 직접 하므로 `openSavedFile` 만 구현한다.
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
    default:
      result(FlutterMethodNotImplemented)
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
