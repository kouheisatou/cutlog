import Foundation
import WebKit

/// 撮った動画をサーバへ送る係。
///
/// 大きなファイルを JavaScript 経由で橋渡しすると、base64 化でメモリが跳ねるうえ遅い。
/// そこでネイティブから直接 `POST {baseUrl}/api/logs/{logId}/cuts` する。
///
/// 認証は WKWebView が持っているセッション Cookie（cutlog_session）をそのまま借りる。
/// アプリ側で独自にログインを持たせると、Web とセッションが二重になって食い違うため。
enum CutUploader {

    struct Meta {
        let durationMs: Int
        let takenAt: Date
        let tzOffset: Int
        let facing: String
        let place: LocationProvider.Place?

        func jsonString() -> String {
            var dict: [String: Any] = [
                "kind": "video",
                "durationMs": durationMs,
                "takenAt": ISO8601DateFormatter.cutlog.string(from: takenAt),
                "tzOffset": tzOffset,
                "facing": facing,
                "source": "camera",
            ]
            // 場所は取れたときだけ入れる。null を送るとサーバ側で無駄に弾かれる。
            if let place {
                dict["lat"] = place.latitude
                dict["lon"] = place.longitude
                dict["accuracy"] = place.accuracy
            }
            let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data()
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    enum UploadError: LocalizedError {
        case notLoggedIn
        case server(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return "ログインしていません。アプリの画面でログインし直してください。"
            case .server(let status, let body):
                if status == 401 || status == 403 { return "権限がありません（\(status)）" }
                let detail = body.isEmpty ? "" : "：\(body.prefix(120))"
                return "サーバがエラーを返しました（\(status)）\(detail)"
            }
        }
    }

    /// multipart/form-data で送る。フィールド名は Web と同じ `file` と `meta`。
    static func upload(
        fileURL: URL,
        to request: CaptureRequest,
        meta: Meta,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        cookieHeader(for: request.baseURL) { cookieHeader in
            guard let cookieHeader, !cookieHeader.isEmpty else {
                completion(.failure(UploadError.notLoggedIn))
                return
            }

            let boundary = "cutlog-\(UUID().uuidString)"
            let body: URL
            do {
                body = try makeMultipartFile(
                    fileURL: fileURL, metaJSON: meta.jsonString(), boundary: boundary)
            } catch {
                completion(.failure(error))
                return
            }

            var req = URLRequest(url: request.uploadURL)
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            // Cookie は自分で組み立てて載せる。
            // URLSession の自動 Cookie 管理に任せると WKWebView の保管庫とは別物になり、
            // セッションが渡らないことがあるため。
            req.httpShouldHandleCookies = false
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            // サーバの CSRF/参照元チェックに引っかからないよう、Web と同じ出自を名乗る
            req.setValue(request.baseURL.absoluteString, forHTTPHeaderField: "Origin")
            req.setValue(request.baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            // 動画は数 MB になるので、既定の 60 秒では足りないことがある
            req.timeoutInterval = 120

            let task = URLSession.shared.uploadTask(with: req, fromFile: body) { data, response, error in
                // 組み立てた一時ファイルは必ず片付ける
                try? FileManager.default.removeItem(at: body)

                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    DispatchQueue.main.async {
                        completion(.failure(UploadError.server(status: status, body: text)))
                    }
                    return
                }
                DispatchQueue.main.async { completion(.success(())) }
            }
            task.resume()
        }
    }

    // MARK: - Cookie

    /// WKWebView が持っている Cookie から、この URL に送るべきものだけを Cookie ヘッダに組む。
    private static func cookieHeader(for url: URL, completion: @escaping (String?) -> Void) {
        // httpCookieStore の API はメインスレッドから呼ぶ約束になっている
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let matched = cookies.filter { matches(cookie: $0, url: url) }
                guard !matched.isEmpty else {
                    completion(nil)
                    return
                }
                // URLSession 側にも流しておく（リダイレクトなどで拾われる可能性に備える）
                matched.forEach { HTTPCookieStorage.shared.setCookie($0) }
                let header = HTTPCookie.requestHeaderFields(with: matched)["Cookie"]
                completion(header)
            }
        }
    }

    /// Cookie の domain / path / secure がこの URL に合うか。
    private static func matches(cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain.lowercased()
        // 先頭のドットはサブドメイン共有の印。cookie.domain == host も許す。
        let domainOK = domain.hasPrefix(".")
            ? (host == String(domain.dropFirst()) || host.hasSuffix(domain))
            : host == domain
        guard domainOK else { return false }

        let path = url.path.isEmpty ? "/" : url.path
        guard path.hasPrefix(cookie.path) || cookie.path == "/" else { return false }

        // secure な Cookie は https にしか送らない
        if cookie.isSecure && url.scheme?.lowercased() != "https" { return false }
        if let expires = cookie.expiresDate, expires < Date() { return false }
        return true
    }

    // MARK: - multipart の組み立て

    /// 本文をメモリに載せるとカット動画のサイズによっては苦しいので、
    /// 一時ファイルに書き出して uploadTask(fromFile:) に渡す。
    private static func makeMultipartFile(
        fileURL: URL, metaJSON: String, boundary: String
    ) throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutlog-body-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }

        func write(_ s: String) throws {
            try handle.write(contentsOf: Data(s.utf8))
        }

        // meta（JSON 文字列）
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"meta\"\r\n")
        try write("Content-Type: application/json; charset=utf-8\r\n\r\n")
        try write(metaJSON)
        try write("\r\n")

        // file（動画本体）
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        try write("Content-Type: video/mp4\r\n\r\n")

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        // 1MB ずつ流し込む。全部読むとメモリが跳ねる。
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        try write("\r\n--\(boundary)--\r\n")
        return out
    }
}

extension ISO8601DateFormatter {
    /// サーバは takenAt をそのまま保存し localDate の判定にも使う。
    /// Web 側は Date#toISOString() 相当（ミリ秒つき UTC）なので、それに揃える。
    static let cutlog: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}
