import CoreLocation

/// The center of the Kaaba (WGS84).
public enum Kaaba {
    public static let latitude = 21.422487
    public static let longitude = 39.826206
    public static let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

/// Qibla bearing and distance to the Kaaba.
///
/// Models the Earth as the WGS84 ellipsoid (Vincenty's inverse formula) — the same model GPS uses —
/// which removes the up-to-~0.3° error of the usual spherical formula.
public enum QiblaCalculator {

    public struct Result: Equatable {
        /// Degrees clockwise from true north, 0..<360.
        public let bearing: Double
        /// Meters.
        public let distance: Double

        public init(bearing: Double, distance: Double) {
            self.bearing = bearing
            self.distance = distance
        }
    }

    // WGS84
    private static let a = 6_378_137.0
    private static let f = 1 / 298.257_223_563
    private static let b = (1 - f) * a

    /// Qibla from the given coordinate. Falls back to the spherical solution if Vincenty does not converge.
    public static func qibla(from coordinate: CLLocationCoordinate2D) -> Result {
        qibla(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Qibla from the given latitude / longitude in degrees.
    public static func qibla(latitude: Double, longitude: Double) -> Result {
        vincenty(lat1: latitude, lon1: longitude, lat2: Kaaba.latitude, lon2: Kaaba.longitude)
            ?? spherical(lat1: latitude, lon1: longitude, lat2: Kaaba.latitude, lon2: Kaaba.longitude)
    }

    /// Vincenty's inverse formula. Returns nil if it fails to converge, which only happens
    /// very close to the antipode of the destination (for the Kaaba: the South Pacific).
    public static func vincenty(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Result? {
        let L = (lon2 - lon1).radians
        let U1 = atan((1 - f) * tan(lat1.radians))
        let U2 = atan((1 - f) * tan(lat2.radians))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinU2 = sin(U2), cosU2 = cos(U2)

        var lambda = L
        var sinLambda = 0.0, cosLambda = 0.0
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0
        var cosSqAlpha = 0.0, cos2SigmaM = 0.0
        var converged = false

        for _ in 0..<200 {
            sinLambda = sin(lambda)
            cosLambda = cos(lambda)
            let t1 = cosU2 * sinLambda
            let t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
            sinSigma = sqrt(t1 * t1 + t2 * t2)
            // Same point: bearing is undefined.
            if sinSigma == 0 { return Result(bearing: 0, distance: 0) }

            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            // Line along the equator: cosSqAlpha = 0.
            cos2SigmaM = cosSqAlpha != 0 ? cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha : 0

            let C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
            let previous = lambda
            lambda = L + (1 - C) * f * sinAlpha
                * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))

            if abs(lambda - previous) < 1e-12 {
                converged = true
                break
            }
        }
        guard converged else { return nil }

        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
            - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        let distance = b * A * (sigma - deltaSigma)

        let azimuth = atan2(cosU2 * sinLambda, cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
        return Result(bearing: normalized(azimuth.degrees), distance: distance)
    }

    /// Great-circle (spherical) solution with a haversine distance on the mean Earth radius.
    public static func spherical(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Result {
        let phi1 = lat1.radians, phi2 = lat2.radians
        let deltaPhi = (lat2 - lat1).radians
        let deltaLambda = (lon2 - lon1).radians

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)

        let h = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let distance = 2 * 6_371_008.8 * atan2(sqrt(h), sqrt(1 - h))

        return Result(bearing: normalized(atan2(y, x).degrees), distance: distance)
    }

    /// Wraps an angle into 0..<360 (negatives included).
    public static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Shortest signed difference between two angles, -180...180 (359° → 1° = +2°).
    public static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
