import AVFoundation
import UIKit

/// 撮影画面。Web の「カメラ」タブから呼ばれ、録って、上げて、閉じる。
///
/// 見た目は Web の撮影画面（web/index.html の #captureDialog）をなぞっている。
/// 同じアプリの同じ操作なので、殻の中と外で当たりが変わらない方がよいためである。
///   上： × ／ 記録先 ／ 前後の切り替え
///   下： 倍率の目印 ／ まるいシャッター（外周が一周したら録り終わり） ／ 「動画」
///
/// 横向きで撮るのは、まとめ動画を横で作るためと、
/// シネマティック手ぶれ補正が横構図を前提に効きやすいためである。
final class CaptureViewController: UIViewController {

    enum Outcome {
        /// 撮って上げ終わった。Web を撮った日の画面へ連れて行くために、作られたカットを渡す。
        case success(CutUploader.Created)
        case cancelled
        case failure(String)
    }

    private let request: CaptureRequest
    private let finish: (Outcome) -> Void

    private let camera = CameraSession()
    private let location = LocationProvider()

    private var previewLayer: AVCaptureVideoPreviewLayer?

    // 上
    private let topBar = GradientView(direction: .down)
    private let closeButton = UIButton(type: .system)
    private let destLabel = UILabel()
    private let flipButton = UIButton(type: .system)

    // 下
    private let bottomBar = GradientView(direction: .up)
    private let zoomRow = UIStackView()
    private let shutter = ShutterButton()
    private let stabilizationLabel = UILabel()
    private let kindLabel = UILabel()

    // 真ん中
    private let hintLabel = PaddedLabel()
    private let busyView = UIActivityIndicatorView(style: .large)

    private var recordingStartedAt: Date?
    private var didFinish = false
    private var didStartSetup = false

    init(request: CaptureRequest, finish: @escaping (Outcome) -> Void) {
        self.request = request
        self.finish = finish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - ライフサイクル

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
    }

    /// カメラの用意は「画面が出きってから」始める。
    ///
    /// viewDidLoad で始めると、カメラが無い・許可が無いといった失敗が
    /// せり上がりのアニメーションの最中に返ってくる。その最中の dismiss は UIKit に無視され、
    /// しかも didFinish が立つので閉じるボタンも効かなくなり、撮影画面から出られなくなる。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartSetup else { return }
        didStartSetup = true

        camera.configure { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // 位置は撮り終わってから使うので、ここで先に走らせておく。
                // 測位を待って撮影開始が遅れるのが一番困る。
                //
                // ただし「カメラが用意できてから」でないと始めない。
                // カメラで失敗するとこの画面はすぐ閉じるが、位置情報の許可ダイアログは
                // 画面より長生きして Web の上に取り残されてしまうためである。
                location.start()
                attachPreview()
                buildZoomStops()
                updateStabilizationLabel()
                showOpeningHints()
                shutter.isEnabled = true
                flipButton.isEnabled = true
                UIView.animate(withDuration: 0.2) { self.shutter.alpha = 1 }
            case .failure(let error):
                complete(.failure(error.localizedDescription))
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        location.stop()
        camera.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateRotation()
    }

    // 撮影は横向き固定。Info.plist で横を許可し、ここで縦を落とす。
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - 画面

    private func buildUI() {
        // ── 上のバー ──────────────────────────────────
        // Web と同じく、黒からの薄いぼかしを敷いてから中身を置く。
        // 明るい景色の上でも白い字が読めるようにするため。
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: Self.iconConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(tapClose), for: .touchUpInside)
        closeButton.accessibilityLabel = "閉じる"

        destLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        destLabel.font = .systemFont(ofSize: 12, weight: .regular)
        destLabel.text = request.logName.isEmpty ? "" : "記録先 \(request.logName)"
        destLabel.lineBreakMode = .byTruncatingTail

        flipButton.setImage(
            UIImage(systemName: "arrow.triangle.2.circlepath.camera", withConfiguration: Self.iconConfig),
            for: .normal)
        flipButton.tintColor = .white
        flipButton.isEnabled = false
        flipButton.addTarget(self, action: #selector(tapFlip), for: .touchUpInside)
        flipButton.accessibilityLabel = "前と後ろを切り替える"

        let top = UIStackView(arrangedSubviews: [closeButton, destLabel, UIView(), flipButton])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 10
        top.translatesAutoresizingMaskIntoConstraints = false

        // ── 下のバー ──────────────────────────────────
        zoomRow.axis = .horizontal
        zoomRow.spacing = 6
        zoomRow.alignment = .center

        shutter.isEnabled = false
        shutter.alpha = 0.4
        shutter.addTarget(self, action: #selector(tapShutter), for: .touchUpInside)
        shutter.accessibilityLabel = "撮る"

        // 効いている手ぶれ補正を画面に出す。
        // 端末の補正を使うことがこのアプリの目的なので、目で確かめられるようにした。
        stabilizationLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        stabilizationLabel.font = .systemFont(ofSize: 10, weight: .regular)
        stabilizationLabel.numberOfLines = 2
        stabilizationLabel.text = "手ぶれ補正\n確認中"

        // Web の右下にある「動画」。撮れるものが動画だけであることを示す。
        kindLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        kindLabel.font = .systemFont(ofSize: 11, weight: .medium)
        kindLabel.text = "動画"
        kindLabel.textAlignment = .right

        // 左・中・右で幅を等しくして、シャッターを画面のちょうど真ん中に置く。
        // 幅を成り行きにするとシャッターが左右に寄って、構えたときに指の位置が定まらない。
        let leftSlot = UIView()
        let rightSlot = UIView()
        [stabilizationLabel, kindLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        leftSlot.addSubview(stabilizationLabel)
        rightSlot.addSubview(kindLabel)

        let row = UIStackView(arrangedSubviews: [leftSlot, shutter, rightSlot])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill

        let bottom = UIStackView(arrangedSubviews: [zoomRow, row])
        bottom.axis = .vertical
        bottom.alignment = .center
        bottom.spacing = 10
        bottom.translatesAutoresizingMaskIntoConstraints = false

        // ── 真ん中 ────────────────────────────────────
        hintLabel.textColor = .white
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textAlignment = .center
        hintLabel.layer.cornerRadius = 12
        hintLabel.clipsToBounds = true
        hintLabel.text = "カメラを準備しています…"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        busyView.color = .white
        busyView.hidesWhenStopped = true
        busyView.translatesAutoresizingMaskIntoConstraints = false

        [topBar, bottomBar, hintLabel, busyView].forEach(view.addSubview)
        topBar.addSubview(top)
        bottomBar.addSubview(bottom)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // 帯そのものは画面の端まで伸ばし、中身だけを安全な範囲に収める。
            // こうしないと、帯の切れ目がノッチの脇に浮いて見える。
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: top.bottomAnchor, constant: 14),

            top.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            top.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            top.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            flipButton.widthAnchor.constraint(equalToConstant: 44),
            flipButton.heightAnchor.constraint(equalToConstant: 44),

            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.topAnchor.constraint(equalTo: bottom.topAnchor, constant: -14),

            bottom.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            bottom.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            bottom.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
            row.widthAnchor.constraint(equalTo: bottom.widthAnchor),
            leftSlot.widthAnchor.constraint(equalTo: rightSlot.widthAnchor),
            leftSlot.heightAnchor.constraint(equalTo: shutter.heightAnchor),

            stabilizationLabel.leadingAnchor.constraint(equalTo: leftSlot.leadingAnchor),
            stabilizationLabel.centerYAnchor.constraint(equalTo: leftSlot.centerYAnchor),
            stabilizationLabel.trailingAnchor.constraint(lessThanOrEqualTo: leftSlot.trailingAnchor, constant: -8),
            kindLabel.trailingAnchor.constraint(equalTo: rightSlot.trailingAnchor),
            kindLabel.centerYAnchor.constraint(equalTo: rightSlot.centerYAnchor),

            hintLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            hintLabel.heightAnchor.constraint(equalToConstant: 24),

            busyView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            busyView.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
        ])
    }

    private static let iconConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)

    /// 倍率の目印。Web の .zoom-stops と同じく、押すとその倍率に飛ぶ粒を並べる。
    private func buildZoomStops() {
        zoomRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let stops = camera.zoomStops
        guard stops.count > 1 else { return }
        let base = camera.zoomBase
        for stop in stops {
            let shown = stop / base
            let button = ZoomStopButton()
            // 0.5× のように小数が要るものだけ小数で出す
            button.setTitle(shown < 1 || shown != shown.rounded()
                            ? String(format: "%.1f×", shown) : String(format: "%.0f×", shown),
                            for: .normal)
            button.factor = stop
            button.addTarget(self, action: #selector(tapZoomStop(_:)), for: .touchUpInside)
            zoomRow.addArrangedSubview(button)
        }
        markActiveZoom()
    }

    private func markActiveZoom() {
        let now = camera.zoomFactor
        for case let b as ZoomStopButton in zoomRow.arrangedSubviews {
            b.isOn = abs(b.factor - now) < 0.05
        }
    }

    private func attachPreview() {
        let layer = AVCaptureVideoPreviewLayer(session: camera.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        updateRotation()
    }

    private func updateRotation() {
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .landscapeRight
        camera.updateRotation(for: orientation)
        // プレビューの向きは録画とは別の接続なので、こちらにも同じ角度を入れる
        if let connection = previewLayer?.connection {
            let angle: CGFloat
            switch orientation {
            case .landscapeRight: angle = 0
            case .portrait: angle = 90
            case .landscapeLeft: angle = 180
            case .portraitUpsideDown: angle = 270
            default: angle = 0
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    /// 最初に出す短い注意書き。
    ///
    /// ★手ぶれ補正の断りを先に出すのは、これが実際に迷うところだからである。
    ///   iOS の補正は録画される映像にだけ効き、この画面（プレビュー）には乗らない。
    ///   知らないと「効いていない」と見えてしまう。
    private func showOpeningHints() {
        if camera.activeStabilizationName != "なし" {
            hintLabel.text = "手ぶれ補正は録画された映像にだけ効きます"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, !camera.isRecording else { return }
                UIView.transition(with: hintLabel, duration: 0.2, options: .transitionCrossDissolve) {
                    self.hintLabel.text = "横向きの範囲で記録されます"
                }
            }
        } else {
            hintLabel.text = "横向きの範囲で記録されます"
        }
    }

    /// 効いている補正を出す。
    /// ★プレビューには補正が乗らないので、画を見ても効いているかは分からない。
    ///   ここの表示だけが手がかりになる。
    private func updateStabilizationLabel() {
        stabilizationLabel.text = "手ぶれ補正\n\(camera.activeStabilizationName)"
    }

    // MARK: - 操作

    @objc private func tapClose() {
        if camera.isRecording { camera.stopRecording() }
        // すでに結果を返したのに画面が残っている場合の逃げ道。
        // complete は一度きりなので、ここで自分から閉じないと出られなくなる。
        guard !didFinish else {
            presentingViewController?.dismiss(animated: true)
            return
        }
        complete(.cancelled)
    }

    @objc private func tapFlip() {
        guard !camera.isRecording else { return }
        flipButton.isEnabled = false
        camera.flip { [weak self] in
            guard let self else { return }
            flipButton.isEnabled = true
            buildZoomStops()
            updateStabilizationLabel()
        }
    }

    @objc private func tapZoomStop(_ sender: ZoomStopButton) {
        camera.setZoom(sender.factor)
        markActiveZoom()
    }

    @objc private func tapShutter() {
        guard !camera.isRecording else { return }
        shutter.isEnabled = false
        closeButton.isHidden = true
        flipButton.isHidden = true
        hintLabel.isHidden = true
        recordingStartedAt = Date()
        // 外周が request.seconds かけて一周する。残り時間はこれで分かるので、数字は出さない。
        shutter.startRecording(seconds: request.seconds)

        camera.startRecording(seconds: request.seconds) { [weak self] result in
            guard let self else { return }
            shutter.stopRecording()
            // 録画が始まって初めて「実際に効いている」補正が分かる
            updateStabilizationLabel()
            switch result {
            case .success(let url):
                upload(url)
            case .failure(let error):
                complete(.failure(error.localizedDescription))
            }
        }
    }

    // MARK: - アップロード

    private func upload(_ fileURL: URL) {
        hintLabel.isHidden = false
        hintLabel.text = "送信中…"
        busyView.startAnimating()
        shutter.isHidden = true

        // 実測した長さを使う。指定秒とはわずかにずれる（フレーム境界で止まるため）。
        let durationMs = Int((Date().timeIntervalSince(recordingStartedAt ?? Date())) * 1000)
        let meta = CutUploader.Meta(
            durationMs: durationMs,
            takenAt: recordingStartedAt ?? Date(),
            tzOffset: request.tzOffset,
            facing: camera.facing,
            place: location.place
        )

        CutUploader.upload(fileURL: fileURL, to: request, meta: meta) { [weak self] result in
            // 送り終えたら一時ファイルは要らない
            try? FileManager.default.removeItem(at: fileURL)
            guard let self else { return }
            busyView.stopAnimating()
            switch result {
            case .success(let created):
                complete(.success(created))
            case .failure(let error):
                complete(.failure(error.localizedDescription))
            }
        }
    }

    // MARK: - 終了

    /// 二重に呼ばれても一度しか通さない（タイマーと利用者の操作が重なることがある）。
    private func complete(_ outcome: Outcome) {
        guard !didFinish else { return }
        didFinish = true
        shutter.stopRecording()
        camera.stop()
        location.stop()
        finish(outcome)
    }
}

// MARK: - 部品

/// Web の .shutter と同じ見た目。
/// 白い輪の中に赤い丸があり、録っているあいだは丸が角丸の四角に縮み、
/// 外周が 1 カットぶんの長さでちょうど一周する。
private final class ShutterButton: UIButton {
    private let track = CAShapeLayer()
    private let run = CAShapeLayer()
    private let dot = UIView()

    private static let size: CGFloat = 78
    private static let dotSize: CGFloat = 58

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])

        for shape in [track, run] {
            shape.fillColor = nil
            shape.lineWidth = 5
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        track.strokeColor = UIColor.white.withAlphaComponent(0.32).cgColor
        run.strokeColor = UIColor.white.cgColor
        run.strokeEnd = 0

        dot.backgroundColor = UIColor(red: 0.898, green: 0.282, blue: 0.302, alpha: 1)  // #e5484d
        dot.layer.cornerRadius = Self.dotSize / 2
        dot.isUserInteractionEnabled = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotWidth, dotHeight,
        ])
    }

    private lazy var dotWidth = dot.widthAnchor.constraint(equalToConstant: Self.dotSize)
    private lazy var dotHeight = dot.heightAnchor.constraint(equalToConstant: Self.dotSize)

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = run.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        // 12 時から時計回りに描く
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: rect.width / 2,
            startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true
        ).cgPath
        track.path = path
        run.path = path
        track.frame = bounds
        run.frame = bounds
    }

    func startRecording(seconds: Double) {
        let shrink = CABasicAnimation(keyPath: "strokeEnd")
        shrink.fromValue = 0
        shrink.toValue = 1
        shrink.duration = seconds
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        run.add(shrink, forKey: "run")

        dotWidth.constant = 26
        dotHeight.constant = 26
        UIView.animate(withDuration: 0.16) {
            self.dot.layer.cornerRadius = 6
            self.layoutIfNeeded()
        }
    }

    func stopRecording() {
        run.removeAnimation(forKey: "run")
        run.strokeEnd = 0
        dotWidth.constant = Self.dotSize
        dotHeight.constant = Self.dotSize
        UIView.animate(withDuration: 0.16) {
            self.dot.layer.cornerRadius = Self.dotSize / 2
            self.layoutIfNeeded()
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }
}

/// Web の .zoom-stop と同じ、丸い小さな倍率の粒。
private final class ZoomStopButton: UIButton {
    var factor: CGFloat = 1
    var isOn = false {
        didSet {
            backgroundColor = isOn ? .white : UIColor.black.withAlphaComponent(0.5)
            setTitleColor(isOn ? .black : .white, for: .normal)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        layer.cornerRadius = 14
        clipsToBounds = true
        isOn = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// 上下の帯。Web と同じ、黒からの薄いぼかし。
/// 明るい景色を撮っているときでも、白い字とアイコンが読めるようにするためのもの。
private final class GradientView: UIView {
    enum Direction { case up, down }

    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(direction: Direction) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true
        guard let gradient = layer as? CAGradientLayer else { return }
        let dark = UIColor.black.withAlphaComponent(direction == .down ? 0.55 : 0.6).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        gradient.colors = direction == .down ? [dark, clear] : [clear, dark]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// 左右に余白のある丸い注意書き。Web の .cam-hint に当たる。
private final class PaddedLabel: UILabel {
    private let inset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right, height: s.height)
    }
}
