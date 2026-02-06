import Foundation
import MapKit

enum DirectionsMode {
    case driving, walking, transit

    var launchValue: String {
        switch self {
        case .driving: return MKLaunchOptionsDirectionsModeDriving
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        }
    }
}

enum Directions {
    static func openInAppleMaps(title: String,
                                coordinate: CLLocationCoordinate2D,
                                mode: DirectionsMode) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = title

        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: mode.launchValue
        ])
    }
}
