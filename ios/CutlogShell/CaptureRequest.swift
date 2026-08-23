import Foundation

/// Web から降ってくる撮影の注文。
/// 契約:
///   window.webkit.messageHandlers.cutlog.postMessage(
///     { type: "capture", baseUrl, logId, logName, seconds, tzOffset })
struct CaptureRequest {
    let baseURL: URL
    let logId: String
    /// 記録先の名前。撮影画面の上に出すためだけに使う（空でも撮影はできる）。
    let logName: String
    let seconds: Double
    /// JavaScript の getTimezoneOffset() と同じ向き（日本なら -540）。
    /// サーバがこれを使って「現地の日付」を決めるので、そのまま渡す。
    let tzOffset: Int

    init?(message body: Any) {
        guard let dict = body as? [String: Any],
              (dict["type"] as? String) == "capture",
              let logId = dict["logId"] as? String, !logId.isEmpty
        else { return nil }

        // baseUrl は location.origin なのでそのまま URL になるはずだが、
        // 万一欠けていたらビルド時に埋め込んだ住所へ落とす。
        self.baseURL = (dict["baseUrl"] as? String)
            .flatMap { Self.normalize($0) } ?? BuildConfig.baseURL
        self.logId = logId
        self.logName = (dict["logName"] as? String) ?? ""
        // 秒数は Number でも String でも来うるので両対応にする。範囲外は握り潰す。
        let rawSeconds = (dict["seconds"] as? NSNumber)?.doubleValue
            ?? Double((dict["seconds"] as? String) ?? "") ?? 3
        self.seconds = min(max(rawSeconds, 1), 60)
        self.tzOffset = (dict["tzOffset"] as? NSNumber)?.intValue
            ?? Int((dict["tzOffset"] as? String) ?? "")
            ?? TimeZone.current.jsStyleOffsetMinutes
    }

    /// Web から来た文字列を URL にする。末尾のスラッシュは組み立てで二重になるので落とす。
    private static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// アップロード先。`POST {baseUrl}/api/logs/{logId}/cuts`
    var uploadURL: URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("logs")
            .appendingPathComponent(logId)
            .appendingPathComponent("cuts")
    }
}

extension TimeZone {
    /// JavaScript の Date#getTimezoneOffset() と同じ符号（UTC より東は負）。
    var jsStyleOffsetMinutes: Int { -secondsFromGMT() / 60 }
}
