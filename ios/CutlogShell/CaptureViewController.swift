import AVFoundation
import UIKit

/// 撮影画面。Web の「カメラ」タブから呼ばれ、録って、上げて、閉じる。
///
/// 横向きで撮るのは、まとめ動画を横で作るためと、
/// シネマティック手ぶれ補正が横構図を前提に効きやすいためである。
final class CaptureViewController: UIViewController {

    enum Outcome {
        case success
        case cancelled
        case failure(String)
    }

    private let request: CaptureRequest
    private let finish: (Outcome) -> Void

    private let camera = CameraSession()
    private let location = LocationProvider()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let shutter = UIButton(type: .custom)
    private let closeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let stabilizationLabel = UILabel()
    private let countdownLabel = UILabel()
    private let busyView = UIActivityIndicatorView(style: .large)

    private var countdownTimer: Timer?
    private var recordingStartedAt: Date?
    private var didFinish = false

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

        // 位置は撮り終わってから使うので、ここで先に走らせておく。
        // 測位を待って撮影開始が遅れるのが一番困る。
        location.start()

        camera.configure { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                attachPreview()
                stabilizationLabel.text = "手ぶれ補正: \(camera.stabilizationLabel)"
                statusLabel.text = "\(Int(request.seconds)) 秒撮ります"
                shutter.isEnabled = true
                shutter.alpha = 1
            case .failure(let error):
                complete(.failure(error.localizedDescription))
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        countdownTimer?.invalidate()
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
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.text = "カメラを準備しています…"

        // 効いている手ぶれ補正を画面に出す。
        // このアプリの目的そのものなので、動いていることを目で確かめられるようにした。
        stabilizationLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        stabilizationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        stabilizationLabel.text = "手ぶれ補正: 確認中"

        let info = UIStackView(arrangedSubviews: [statusLabel, stabilizationLabel])
        info.axis = .vertical
        info.spacing = 2
        info.alignment = .center
        info.translatesAutoresizingMaskIntoConstraints = false

        countdownLabel.textColor = .white
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        countdownLabel.textAlignment = .center
        countdownLabel.alpha = 0
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false

        shutter.backgroundColor = .systemRed
        shutter.layer.cornerRadius = 36
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.white.cgColor
        shutter.isEnabled = false
        shutter.alpha = 0.4
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addTarget(self, action: #selector(tapShutter), for: .touchUpInside)
        shutter.accessibilityLabel = "録画を始める"

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(tapClose), for: .touchUpInside)
        closeButton.accessibilityLabel = "やめる"

        busyView.color = .white
        busyView.hidesWhenStopped = true
        busyView.translatesAutoresizingMaskIntoConstraints = false

        [info, countdownLabel, shutter, closeButton, busyView].forEach(view.addSubview)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            info.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            info.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),

            countdownLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),

            // 横向きなので、シャッターは右端の中央に置く（親指が届く位置）
            shutter.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            shutter.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72),

            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            busyView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            busyView.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
        ])
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

    // MARK: - 操作

    @objc private func tapClose() {
        if camera.isRecording { camera.stopRecording() }
        complete(.cancelled)
    }

    @objc private func tapShutter() {
        guard !camera.isRecording else { return }
        shutter.isEnabled = false
        shutter.alpha = 0.4
        closeButton.isHidden = true
        recordingStartedAt = Date()
        statusLabel.text = "録画中"
        startCountdown()

        camera.startRecording(seconds: request.seconds) { [weak self] result in
            guard let self else { return }
            countdownTimer?.invalidate()
            countdownLabel.alpha = 0
            switch result {
            case .success(let url):
                upload(url)
            case .failure(let error):
                complete(.failure(error.localizedDescription))
            }
        }
    }

    private func startCountdown() {
        countdownLabel.alpha = 1
        let end = Date().addingTimeInterval(request.seconds)
        countdownLabel.text = String(format: "%.1f", request.seconds)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { return }
            let left = max(0, end.timeIntervalSinceNow)
            countdownLabel.text = String(format: "%.1f", left)
            // 録画が始まって初めて「実際に効いている」補正が分かる。
            // 目的そのものなので、指定した値ではなく効いている値を出す。
            stabilizationLabel.text = "手ぶれ補正: \(camera.activeStabilizationName)"
            if left <= 0 { timer.invalidate() }
        }
    }

    // MARK: - アップロード

    private func upload(_ fileURL: URL) {
        statusLabel.text = "送信中…"
        busyView.startAnimating()
        shutter.isHidden = true

        // 実測した長さを使う。指定秒とはわずかにずれる（フレーム境界で止まるため）。
        let durationMs = Int((Date().timeIntervalSince(recordingStartedAt ?? Date())) * 1000)
        let meta = CutUploader.Meta(
            durationMs: durationMs,
            takenAt: recordingStartedAt ?? Date(),
            tzOffset: request.tzOffset,
            // 背面カメラで撮っているので environment 固定。Web 側の値と揃える。
            facing: "environment",
            place: location.place
        )

        CutUploader.upload(fileURL: fileURL, to: request, meta: meta) { [weak self] result in
            // 送り終えたら一時ファイルは要らない
            try? FileManager.default.removeItem(at: fileURL)
            guard let self else { return }
            busyView.stopAnimating()
            switch result {
            case .success:
                complete(.success)
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
        countdownTimer?.invalidate()
        camera.stop()
        location.stop()
        finish(outcome)
    }
}
