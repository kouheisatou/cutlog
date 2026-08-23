import UIKit

// ストーリーボードもシーンも使わない。CLI だけでビルド・確認したいので、
// 生成物（xib/storyboard のコンパイル）を増やさず、コードで窓を組む。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    // 撮影画面だけを横向きにしたいので、向きの可否は「今いちばん上の画面」に委ねる。
    // Info.plist では縦横どちらも許可しておき、実際の制限はここから下ろす。
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        window?.rootViewController?.topMostPresented.supportedInterfaceOrientations ?? .portrait
    }
}

extension UIViewController {
    /// modal で積み上がった先頭の画面を返す。
    var topMostPresented: UIViewController {
        presentedViewController?.topMostPresented ?? self
    }
}
