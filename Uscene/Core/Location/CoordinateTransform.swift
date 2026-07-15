import Foundation
import CoreLocation

enum CoordinateTransform {
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    static func outOfChina(longitude: Double, latitude: Double) -> Bool {
        !(longitude >= 80.0 && longitude <= 130.0 && latitude >= 18.0 && latitude <= 50.0)
    }

    static func wgs84ToGcj02(_ coordinate: CLLocationCoordinate2D, forceChina: Bool = false) -> CLLocationCoordinate2D {
        let lng = coordinate.longitude
        let lat = coordinate.latitude
        if outOfChina(longitude: lng, latitude: lat), !forceChina {
            return coordinate
        }
        var dLat = transformLat(lng - 105.0, lat - 35.0)
        var dLng = transformLng(lng - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((6335552.717000426 / (magic * sqrtMagic)) * .pi)
        dLng = (dLng * 180.0) / ((a / sqrtMagic) * .pi)
        return CLLocationCoordinate2D(latitude: lat + dLat, longitude: lng + dLng)
    }

    static func gcj02ToWgs84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lng = coordinate.longitude
        let lat = coordinate.latitude
        if outOfChina(longitude: lng, latitude: lat) {
            return coordinate
        }
        var dLat = transformLat(lng - 105.0, lat - 35.0)
        var dLng = transformLng(lng - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * .pi)
        let mgLat = lat + dLat
        let mgLng = lng + dLng
        return CLLocationCoordinate2D(latitude: lat * 2 - mgLat, longitude: lng * 2 - mgLng)
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLng(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
