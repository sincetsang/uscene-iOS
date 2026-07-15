import SwiftUI
import MapKit

struct SpotAnnotationItem: Identifiable, Hashable {
    let id: Int
    let spot: MapSpot
    let coordinate: CLLocationCoordinate2D

    init(spot: MapSpot) {
        self.id = spot.spot_id
        self.spot = spot
        // Match RN MarkerView: treat API coords as WGS-84 and convert for China display.
        self.coordinate = CoordinateTransform.wgs84ToGcj02(
            spot.coordinate,
            forceChina: spot.is_china == true
        )
    }

    static func == (lhs: SpotAnnotationItem, rhs: SpotAnnotationItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
