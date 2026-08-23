import CoreLocation

/// 撮った場所を、取れたときだけ添える係。
/// 位置は「あれば嬉しい」程度のものなので、断られても撮影は止めない。
/// また、待たされて撮影開始が遅れるのが一番困るので、
/// 撮影画面を開いた時点で先に走らせておき、結果は保存時に取りに行く。
final class LocationProvider: NSObject {
    struct Place {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }

    private let manager = CLLocationManager()
    private(set) var place: Place?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// 許可を求めつつ、許可済みなら測位を始める。
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            // 許可ダイアログは撮影の直前に出る。答えたあと delegate から測位を始める。
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            // 拒否・制限中は何もしない。meta から lat/lon が落ちるだけ。
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            place = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // 精度が測れていない値（負のとき）は捨てる。サーバ側でも弾かれる。
        guard loc.horizontalAccuracy >= 0 else { return }
        place = Place(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 取れなくても撮影は続ける。記録に場所が付かないだけ。
        NSLog("[cutlog] 位置情報を取れませんでした: \(error.localizedDescription)")
    }
}
