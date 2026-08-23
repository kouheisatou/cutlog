import UIKit
import WebKit

/// cutlog の Web を丸ごと表示する殻。
/// 画面は基本的にこれ 1 枚だけで、撮影のときだけネイティブの画面をかぶせる。
final class WebViewController: UIViewController {
    private let serverURL: URL
    private var webView: WKWebView!
    /// 読み込み中に出すクルクル。iOS の作法どおり画面の中央に置く。
    private let spinner = UIActivityIndicatorView(style: .large)
    private var errorView: UIView?

    /// JS 側のハンドラ名。Web の実装（app.js）と揃える。
    private static let bridgeName = "cutlog"

    init(serverURL: URL) {
        self.serverURL = serverURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        // WKUserContentController はハンドラを強参照する。
        // 弱参照の中継（BridgeProxy）を挟んだうえで、念のためここでも外す。
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.bridgeName)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setUpWebView()
        setUpSpinner()
        setUpSettingsGesture()
        load()
    }

    // MARK: - 組み立て

    private func setUpWebView() {
        let config = WKWebViewConfiguration()

        // 全画面プレイヤーへ勝手に飛ばない。カット動画はその場で再生させる。
        config.allowsInlineMediaPlayback = true
        // 自動再生にユーザー操作を要求しない。一覧のサムネ動画が動かなくなるため。
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        // Web → native の窓口。弱参照の中継を挟んで循環参照を避ける。
        config.userContentController.add(BridgeProxy(self), name: Self.bridgeName)

        // Cookie（セッション）を既定のデータストアに置く。
        // アップロードのときにここから取り出して使い回すため、非永続にはしない。
        config.websiteDataStore = .default()

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Web 側が自前でスクロールを持つ画面なので、端でのバウンドは邪魔になる
        webView.scrollView.bounces = false
        // 読み込み中は WebView がまだ何も描いていない。
        // 地の色を画面と揃えておかないと、白や黒が一瞬差し込んで切り替わりが唐突になる。
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.isOpaque = false
        #if DEBUG
        // Safari の Web インスペクタから中を見られるようにする（開発時のみ）
        if webView.responds(to: Selector(("setInspectable:"))) {
            webView.isInspectable = true
        }
        #endif
        view.addSubview(webView)
    }

    private func setUpSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        // 止めたら消えるようにしておく。読み込み中だけ見えていればよい。
        spinner.hidesWhenStopped = true
        // 白地の Web に黒い点が並ぶだけにしたいので、色は文字の副色に合わせる
        spinner.color = .secondaryLabel
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// 読み込み中の見せ方。
    /// 進捗の細い棒はブラウザの作法で、iOS のアプリでは中央のクルクルが自然なのでそちらにした。
    private func setLoading(_ loading: Bool) {
        if loading {
            spinner.alpha = 1
            spinner.startAnimating()
        } else {
            // ぱっと消すと切り替わりが唐突なので、薄くしてから止める
            UIView.animate(withDuration: 0.2) {
                self.spinner.alpha = 0
            } completion: { _ in
                self.spinner.stopAnimating()
            }
        }
    }

    /// 読み込みが固まったときの逃げ道。
    /// 画面を潰したくないので常設のボタンは置かず、2 本指の長押しで再読み込みできるようにする。
    private func setUpSettingsGesture() {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSettingsGesture))
        gesture.numberOfTouchesRequired = 2
        gesture.minimumPressDuration = 1.0
        // Web 側のタップを邪魔しないよう、認識しても他のジェスチャは止めない
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
    }

    @objc private func handleSettingsGesture(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        askToChangeServer()
    }

    private func askToChangeServer() {
        // 接続先はビルド時に決まっているので、ここで変えることはできない。
        // 何に繋いでいるかだけ見せて、再読み込みの手段を出す。
        let alert = UIAlertController(
            title: BuildConfig.appName,
            message: "接続先: \(serverURL.absoluteString)\n（変えるには native.env を書き換えてビルドし直します）",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "再読み込み", style: .default) { [weak self] _ in self?.load() })
        alert.addAction(UIAlertAction(title: "やめる", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(alert, animated: true)
    }

    private func load() {
        removeErrorView()
        setLoading(true)
        // キャッシュの取り違えで古い app.js が出ると橋渡しが噛み合わないため、
        // 起動時だけはサーバに問い合わせ直す。
        var request = URLRequest(url: serverURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        webView.load(request)
    }

    // MARK: - 読み込みに失敗したとき

    private func showErrorView(_ message: String) {
        removeErrorView()
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "つながりませんでした\n\n\(serverURL.absoluteString)\n\n\(message)"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let retry = UIButton(configuration: .filled(), primaryAction: UIAction(title: "もう一度") { [weak self] _ in
            self?.load()
        })

        let stack = UIStackView(arrangedSubviews: [label, retry])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])
        errorView = container
    }

    private func removeErrorView() {
        errorView?.removeFromSuperview()
        errorView = nil
    }

    // MARK: - native → Web

    /// 契約: window.cutlogNative.onResult({ ok: true }) / ({ ok: false, error: "..." })
    private func sendResult(ok: Bool, error: String? = nil) {
        var payload: [String: Any] = ["ok": ok]
        if let error { payload["error"] = error }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"ok":false,"error":"内部エラー"}"#
        // 殻が古い Web を掴んでいて cutlogNative が居ない場合に例外を出さないよう、存在を見てから呼ぶ。
        //
        // 返り値を JS の式のままにしておくと、onResult が async 関数なので Promise が返り、
        // evaluateJavaScript が「対応していないタイプの結果」（WKError 5）を毎回投げていた。
        // 呼べたかどうかだけ分かればよいので、即時関数で包んで真偽値に潰す。
        let js = """
        (function () {
          var n = window.cutlogNative;
          if (!n || typeof n.onResult !== 'function') { return false; }
          n.onResult(\(json));
          return true;
        })();
        """
        webView.evaluateJavaScript(js) { value, err in
            if let err {
                NSLog("[cutlog] onResult の呼び出しに失敗: \(err.localizedDescription)")
            } else if (value as? Bool) != true {
                // Web 側の窓口がまだ用意されていない（読み込み途中など）。
                // 落とすほどのことではないが、結果が握り潰されたことは残しておく。
                NSLog("[cutlog] cutlogNative.onResult がまだ居ないので結果を渡せませんでした")
            }
        }
    }

    // MARK: - 撮影

    private func startCapture(_ request: CaptureRequest) {
        // すでに何かを出しているなら二重に出さない（Web 側の連打対策）
        guard presentedViewController == nil else { return }

        let capture = CaptureViewController(request: request) { [weak self] result in
            guard let self else { return }
            dismiss(animated: true) {
                switch result {
                case .success:
                    self.sendResult(ok: true)
                case .cancelled:
                    // 利用者が自分でやめた場合は Web にトーストを出させたくないので、
                    // 失敗扱いにしつつ空の理由を渡す（app.js は error が無ければ黙る）。
                    self.sendResult(ok: false)
                case .failure(let message):
                    self.sendResult(ok: false, error: message)
                }
            }
        }
        capture.modalPresentationStyle = .fullScreen
        // 横向きへ切り替わる様子を見せたくないので、アニメーションは付ける
        present(capture, animated: true)
    }

    // WebView は縦を基本にする。横は撮影画面だけ。
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}

// MARK: - Web → native

extension WebViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.bridgeName else { return }
        guard let request = CaptureRequest(message: message.body) else {
            sendResult(ok: false, error: "撮影の指示を読み取れませんでした")
            return
        }
        startCapture(request)
    }
}

/// WKUserContentController はメッセージハンドラを強参照する。
/// そのまま WebViewController を渡すと WebView ↔ VC で循環参照になるため、
/// 弱参照で持ち直すだけの中継を挟む。
private final class BridgeProxy: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - ナビゲーション

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        setLoading(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setLoading(false)
        removeErrorView()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handle(error)
    }

    private func handle(_ error: Error) {
        setLoading(false)
        let ns = error as NSError
        // 別の遷移で打ち切られただけのものはエラー画面にしない
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        showErrorView(ns.localizedDescription)
    }

    /// サーバ外のリンク（利用規約など）は Safari に投げる。
    /// 殻の中で外部サイトへ迷い込むと戻れなくなるため。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              let host = url.host, host != serverURL.host,
              UIApplication.shared.canOpenURL(url)
        else {
            decisionHandler(.allow)
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }
}

extension WebViewController: WKUIDelegate {
    /// target="_blank" は新しい WebView を作らず、同じ 1 枚で開く。
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
