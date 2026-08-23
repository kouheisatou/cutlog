import AVFoundation
import UIKit

/// 撮影そのものを受け持つ。
///
/// このアプリの存在理由は「ブラウザの getUserMedia では端末の手ぶれ補正が効かない」ことなので、
/// ここでの主眼は **手ぶれ補正を確実に有効にすること** にある。
/// そのために効く順に気を使っている点が 3 つある。
///
///  1. カメラの選び方  … 複合カメラ（Triple / DualWide）ほど補正も画づくりも良い
///  2. フォーマット    … 手ぶれ補正は「今のフォーマットが対応しているか」で決まる。
///                      4K や高フレームレートの形式は補正が付かないことがあるため 1080p を基本にする
///  3. 接続への設定    … preferredVideoStabilizationMode は
///                      AVCaptureConnection（= 出力ごと）に付ける。セッション構築後でないと効かない
final class CameraSession: NSObject {

    enum SetupError: LocalizedError {
        case noCamera
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noCamera: return "カメラが見つかりませんでした"
            case .cannotAddInput: return "カメラを開けませんでした"
            case .cannotAddOutput: return "録画の準備ができませんでした"
            }
        }
    }

    let session = AVCaptureSession()
    /// セッションの操作はメインスレッドから外す。startRunning は数百ミリ秒かかる。
    private let queue = DispatchQueue(label: "dev.cutlog.shell.camera")
    private let movieOutput = AVCaptureMovieFileOutput()
    private(set) var device: AVCaptureDevice?

    /// 実際に効いている手ぶれ補正。画面に出して確かめられるようにしている。
    private(set) var stabilizationLabel: String = "未設定"

    private var finishHandler: ((Result<URL, Error>) -> Void)?
    private var autoStopTimer: Timer?

    // MARK: - 組み立て

    /// 権限を確かめてからセッションを組む。完了はメインスレッドで返す。
    func configure(completion: @escaping (Result<Void, Error>) -> Void) {
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                completion(.failure(NSError(
                    domain: "dev.cutlog.shell", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "カメラまたはマイクの利用が許可されていません。設定アプリから許可してください。"])))
                return
            }
            queue.async {
                do {
                    try self.buildSession()
                    self.session.startRunning()
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    private func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        // カメラが必須、マイクは音声用。どちらも無いと録画自体が成り立たない。
        AVCaptureDevice.requestAccess(for: .video) { video in
            guard video else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { audio in
                DispatchQueue.main.async { completion(audio) }
            }
        }
    }

    private func buildSession() throws {
        session.beginConfiguration()

        // 【要点 2】4K だと手ぶれ補正の付かないフォーマットが選ばれることがある。
        // 1080p は補正（cinematic 系）が確実に用意されている常用の解像度なので、これを基本にする。
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        // 【要点 1】複合カメラを優先する。
        // 複合カメラは広角と超広角を束ねており、超広角側の余白を使った
        // シネマティック手ぶれ補正（cinematicExtended）が効きやすい。
        guard let camera = Self.pickCamera() else { throw SetupError.noCamera }
        device = camera

        guard let videoInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(videoInput) else { throw SetupError.cannotAddInput }
        session.addInput(videoInput)

        // 音声。取れなくても映像だけで続ける（マイクの無い機種・シミュレータ対策）。
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else { throw SetupError.cannotAddOutput }
        session.addOutput(movieOutput)

        session.commitConfiguration()

        // 【要点 3】手ぶれ補正は commitConfiguration の**あと**に決める。
        // sessionPreset が activeFormat に反映されるのは commit の時点であり、
        // 補正の可否は activeFormat 次第なので、先に訊くと古い形式の答えを拾ってしまう。
        applyStabilization()
    }

    /// 使えるカメラを、手ぶれ補正と画質に効く順で選ぶ。
    /// Triple → DualWide → Wide。前 2 つが無い機種（SE など）でも最後で必ず拾える。
    private static func pickCamera() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera,
        ]
        // DiscoverySession に複数の型を渡すと「機種にある順」で返ってくるため、
        // こちらの優先順を守るには 1 つずつ引く。
        for type in preferred {
            let found = AVCaptureDevice.DiscoverySession(
                deviceTypes: [type], mediaType: .video, position: .back
            ).devices.first
            if let found { return found }
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - 手ぶれ補正（このアプリの主目的）

    private func applyStabilization() {
        guard let connection = movieOutput.connection(with: .video) else {
            stabilizationLabel = "接続なし"
            return
        }
        guard connection.isVideoStabilizationSupported else {
            stabilizationLabel = "この端末は非対応"
            return
        }

        // 強い順に試す。対応の可否は「今の activeFormat」で決まるので、
        // フォーマットを変えたら必ず引き直す。
        if let mode = bestSupportedMode() {
            connection.preferredVideoStabilizationMode = mode
            stabilizationLabel = Self.name(of: mode)
            return
        }

        // ここに来るのは、今のフォーマットが補正に対応していない場合。
        // 「補正が効くこと」が最優先なので、補正に対応するフォーマットを自分で選び直す。
        // activeFormat を触ると sessionPreset は .inputPriority に落ちるが、
        // 補正の無い 1080p より、補正の効く 1080p の方がこのアプリの目的に適う。
        if selectStabilizableFormat(), let mode = bestSupportedMode() {
            connection.preferredVideoStabilizationMode = mode
            stabilizationLabel = Self.name(of: mode) + "（形式を変更）"
            return
        }

        stabilizationLabel = "使える補正なし"
    }

    /// 強い順に、今使える手ぶれ補正を 1 つ返す。
    ///
    /// 対応の可否を持っているのは AVCaptureConnection ではなく AVCaptureDeviceFormat の方
    /// （connection 側には isVideoStabilizationSupported という総合可否しか無い）。
    /// 同じ端末でもフォーマットによって cinematic が付いたり付かなかったりするため、
    /// 必ず「今の activeFormat」に対して訊く。
    private func bestSupportedMode() -> AVCaptureVideoStabilizationMode? {
        guard let format = device?.activeFormat else { return nil }
        for mode in Self.preferredModes where format.isVideoStabilizationModeSupported(mode) {
            return mode
        }
        return nil
    }

    /// 効き目の強い順。手ぶれ補正がこのアプリの主目的なので、常に一番強いものを採る。
    private static var preferredModes: [AVCaptureVideoStabilizationMode] {
        var modes: [AVCaptureVideoStabilizationMode] = []
        // iOS 18 以降のさらに強い補正。使えるなら cinematicExtended より優先する。
        if #available(iOS 18.0, *) {
            modes.append(.cinematicExtendedEnhanced)
        }
        modes.append(contentsOf: [.cinematicExtended, .cinematic, .standard])
        return modes
    }

    /// 手ぶれ補正に対応するフォーマットへ切り替える。切り替えたら true。
    private func selectStabilizableFormat() -> Bool {
        guard let device else { return false }

        // 1080p・30fps を狙う。高解像度や高フレームレートの形式は補正が付かないことが多い。
        let wanted = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == 1920, dims.height == 1080 else { return false }
            guard format.isVideoStabilizationModeSupported(.cinematicExtended)
                    || format.isVideoStabilizationModeSupported(.cinematic) else { return false }
            // 30fps を含む範囲を持つものだけ
            return format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= 30 && 30 <= $0.maxFrameRate
            }
        }

        // cinematicExtended に対応するものを優先する
        let best = wanted.first { $0.isVideoStabilizationModeSupported(.cinematicExtended) } ?? wanted.first
        guard let best else { return false }

        do {
            // 形式の入れ替えは設定ブロックで囲む。囲まないと途中の状態が動いてしまう。
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // activeFormat を直接指定するので、セッション側は入力任せにする
            session.sessionPreset = .inputPriority
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            return true
        } catch {
            NSLog("[cutlog] フォーマットを変えられませんでした: \(error.localizedDescription)")
            return false
        }
    }

    private static func name(of mode: AVCaptureVideoStabilizationMode) -> String {
        if #available(iOS 18.0, *), mode == .cinematicExtendedEnhanced {
            return "シネマティック拡張＋"
        }
        switch mode {
        case .cinematicExtended: return "シネマティック拡張"
        case .cinematic: return "シネマティック"
        case .standard: return "標準"
        case .auto: return "自動"
        case .off: return "なし"
        default: return "不明"
        }
    }

    /// 実際に効いている補正の名前。
    /// 録画が始まるまでは .off のことがあるので、その間は指定した方の名前を返す。
    var activeStabilizationName: String {
        guard let connection = movieOutput.connection(with: .video) else { return "-" }
        let active = connection.activeVideoStabilizationMode
        return active == .off ? stabilizationLabel : Self.name(of: active)
    }

    // MARK: - 向き

    /// 横向きで撮る。
    /// iOS 17 からは videoOrientation ではなく videoRotationAngle を使う。
    /// 0 度が「端末を landscapeRight に構えた状態」に当たるので、そこを基準に合わせる。
    func updateRotation(for interfaceOrientation: UIInterfaceOrientation) {
        guard let connection = movieOutput.connection(with: .video) else { return }
        let angle: CGFloat
        switch interfaceOrientation {
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

    // MARK: - 録画

    var isRecording: Bool { movieOutput.isRecording }

    /// `seconds` 秒だけ録って自動で止める。
    func startRecording(seconds: Double, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !movieOutput.isRecording else { return }
        finishHandler = completion

        // 拡張子で入れ物が決まる。サーバ側は mp4 をそのまま扱えるので mp4 にする
        // （既定の QuickTime .mov のままだと保存時の拡張子が合わない）。
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutlog-\(UUID().uuidString).mp4")

        queue.async { [weak self] in
            guard let self else { return }
            // 保険。タイマーが飛んでも AVFoundation 側で必ず止まるようにする。
            movieOutput.maxRecordedDuration = CMTime(seconds: seconds + 1.0, preferredTimescale: 600)
            movieOutput.startRecording(to: url, recordingDelegate: self)

            DispatchQueue.main.async {
                // 指定秒でこちらから止める。こちらで止めた方が
                // 「上限に達した」エラー扱いにならず、後始末が素直になる。
                self.autoStopTimer?.invalidate()
                self.autoStopTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                    self?.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        queue.async { [weak self] in
            guard let self, movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    func stop() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        queue.async { [weak self] in
            guard let self else { return }
            if movieOutput.isRecording { movieOutput.stopRecording() }
            if session.isRunning { session.stopRunning() }
        }
    }
}

extension CameraSession: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let handler = finishHandler
        finishHandler = nil

        // 上限到達などで error が入っていても、
        // AVErrorRecordingSuccessfullyFinishedKey が true ならファイルは使える。
        let usable = (error as NSError?)?
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)

        DispatchQueue.main.async {
            if let error, !usable {
                try? FileManager.default.removeItem(at: outputFileURL)
                handler?(.failure(error))
            } else {
                handler?(.success(outputFileURL))
            }
        }
    }
}
