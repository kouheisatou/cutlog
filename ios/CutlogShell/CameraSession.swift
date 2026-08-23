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
                    // ★走らせてからでないと、効いている補正は分からない
                    self.confirmStabilization()
                    // 広角（1倍）に合わせてから見せる
                    self.lockToWideLens()
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

        // 【要点 1】広角そのもの（1倍のレンズ）を直に選ぶ。理由は pickCamera を参照。
        guard let camera = Self.pickCamera() else { throw SetupError.noCamera }
        device = camera

        guard let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { throw SetupError.cannotAddInput }
        session.addInput(input)

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

    /// 背面の広角（1倍のレンズ）を選ぶ。前面には切り替えない。
    ///
    /// ★複合カメラ（Triple / DualWide）は使わない。
    ///   複合カメラの videoZoomFactor は「いちばん広いレンズ」を 1.0 とする決まりで、
    ///   超広角を含む機種では 1.0 が 0.5倍にあたる。1倍にするには
    ///   virtualDeviceSwitchOverVideoZoomFactors の最初の値（レンズが切り替わる点）を
    ///   入れ直す必要があり、機種ごとの並びに寄りかかることになる。
    ///   レンズを切り替えないと決めた以上、複合である利点は無いので、
    ///   広角そのものを直に選ぶ。この機器の 1.0 は、定義からして 1倍である。
    private static func pickCamera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back
        ).devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - 画角

    /// 1倍のレンズに合わせる。
    ///
    /// ★カメラは選ばせない。毎日の記録を並べて見るものなので、
    ///   日によって画角が変わらない方がよい。
    /// 広角そのものを選んでいるので、ふつうは 1.0 のままでよい。
    /// 万一 複合カメラを掴んでいた場合に備えて、そのときだけ
    /// レンズの切り替わる点（＝広角の始まり）へ入れ直す。
    func lockToWideLens() {
        guard let device else { return }
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let want = switchOvers.first ?? 1
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = max(1, min(want, device.activeFormat.videoMaxZoomFactor))
        } catch { }
    }

    /// いまの水平画角（度）。1倍のレンズが選べているかを確かめるための手がかり。
    var fieldOfView: Float { device?.activeFormat.videoFieldOfView ?? 0 }

    // MARK: - 手ぶれ補正（このアプリの主目的）
    //
    // 調べて分かったこと（Apple の技術資料・AVFoundation の決まり）:
    //  ・補正は端末ではなく「接続（AVCaptureConnection）」に対して指定する
    //  ・実際に効いているかは activeVideoStabilizationMode でしか分からない。
    //    こちらが指定する preferredVideoStabilizationMode は、あくまで希望である
    //  ・既定は off。指定しない限り一切効かない
    //  ・cinematic 系が使えるのは 1080p30 / 1080p60 の形式だけ。
    //    standard も 16:9 の形式に限られる
    //  ・★プレビューには補正が乗らない。補正は録画される側にだけ効く。
    //    画面を見て「効いていない」と見えるのは、これが理由であることが多い
    //  ・auto を指定すると、形式とフレームレートに合わせて端末が選んでくれる
    //
    // そこで、次の順で決める。
    //  1. 端末に選ばせる（auto）。これが「端末純正のふるまい」にいちばん近い
    //  2. それでも off のままなら、強い順に明示的に指定する
    //  3. 走らせたあとに activeVideoStabilizationMode を読み、効いた値を控える

    private func applyStabilization() {
        guard let connection = movieOutput.connection(with: .video) else {
            stabilizationLabel = "接続なし"
            return
        }
        guard connection.isVideoStabilizationSupported else {
            stabilizationLabel = "この端末は非対応"
            return
        }

        // まず端末に選ばせる。形式とフレームレートを見て、いちばん妥当なものが選ばれる。
        connection.preferredVideoStabilizationMode = .auto
        stabilizationLabel = "自動（確認中）"
    }

    /// セッションを走らせたあとに呼ぶ。
    /// ★ここが肝。走らせる前の activeVideoStabilizationMode は当てにならない。
    /// auto のままで効かなかったときだけ、強いモードを明示して指定し直す。
    private func confirmStabilization() {
        guard let connection = movieOutput.connection(with: .video),
              connection.isVideoStabilizationSupported else { return }

        if connection.activeVideoStabilizationMode != .off {
            stabilizationLabel = Self.name(of: connection.activeVideoStabilizationMode)
            return
        }

        // auto で効かなかった場合。今の形式が許すものを強い順に当てる。
        if let mode = bestSupportedMode() {
            connection.preferredVideoStabilizationMode = mode
            stabilizationLabel = Self.name(of: mode) + "（指定）"
            return
        }

        // 今の形式では無理なので、補正の効く 1080p の形式へ移る。
        if selectStabilizableFormat(), let mode = bestSupportedMode() {
            connection.preferredVideoStabilizationMode = mode
            stabilizationLabel = Self.name(of: mode) + "（形式を変更）"
            return
        }

        stabilizationLabel = "使える補正なし"
    }

    /// 今の形式で使える中で、いちばん強い補正を返す。
    /// ★可否を持っているのは形式（AVCaptureDevice.Format）の方である。
    ///   接続側には isVideoStabilizationSupported という総合可否しか無い。
    private func bestSupportedMode() -> AVCaptureVideoStabilizationMode? {
        guard let format = device?.activeFormat else { return nil }
        for mode in Self.preferredModes where format.isVideoStabilizationModeSupported(mode) {
            return mode
        }
        return nil
    }

    /// 強い順。Enhanced は新しい端末にしか無いので、あるときだけ先頭に入れる。
    private static var preferredModes: [AVCaptureVideoStabilizationMode] {
        var modes: [AVCaptureVideoStabilizationMode] = []
        if #available(iOS 18.0, *) { modes.append(.cinematicExtendedEnhanced) }
        modes.append(contentsOf: [.cinematicExtended, .cinematic, .standard])
        return modes
    }

    /// 補正の効く形式（1080p30 前後）へ移す。
    /// cinematic 系は 1080p30 / 1080p60 にしか無いので、そこを狙う。
    private func selectStabilizableFormat() -> Bool {
        guard let device else { return false }
        let wanted = device.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard d.width == 1920, d.height == 1080 else { return false }
            guard format.isVideoStabilizationModeSupported(.cinematicExtended)
                    || format.isVideoStabilizationModeSupported(.cinematic) else { return false }
            // 30fps を含む範囲のものに絞る（60fps 専用だと明るさが落ちる）
            return format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }
        }
        let best = wanted.first { $0.isVideoStabilizationModeSupported(.cinematicExtended) } ?? wanted.first
        guard let best else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            // activeFormat を直接指定するので、セッション側は入力任せにする
            session.sessionPreset = .inputPriority
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            return true
        } catch {
            return false
        }
    }

    private static func name(of mode: AVCaptureVideoStabilizationMode) -> String {
        if #available(iOS 18.0, *), mode == .cinematicExtendedEnhanced { return "シネマティック拡張+" }
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
    /// ★プレビューには乗らないので、ここの値だけが確かめる手がかりになる。
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
