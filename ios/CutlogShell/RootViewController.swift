import UIKit

/// アプリの土台。接続先はビルド時に埋め込まれているので、
/// 起動したらそのまま WebView を出すだけでよい。
/// （以前はアプリ内で URL を入力させていたが、
///   自己ホストの住所は環境ごとに固定なので native.env からの埋め込みに変えた）
final class RootViewController: UIViewController {
    private var current: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        show(WebViewController(serverURL: BuildConfig.baseURL))
    }

    private func show(_ vc: UIViewController) {
        current?.willMove(toParent: nil)
        current?.view.removeFromSuperview()
        current?.removeFromParent()

        addChild(vc)
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
        current = vc

        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // 向き・ステータスバーの判断は中の画面に任せる
    override var childForStatusBarStyle: UIViewController? { current }
    override var childForStatusBarHidden: UIViewController? { current }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        current?.supportedInterfaceOrientations ?? .portrait
    }
}
