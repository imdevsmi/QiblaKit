import XCTest
import CoreLocation
@testable import QiblaKit

final class QiblaCalculatorTests: XCTestCase {

    /// Widely published great-circle qibla bearings.
    private let references: [(name: String, lat: Double, lon: Double, bearing: Double)] = [
        ("New York", 40.7128, -74.0060, 58.48),
        ("London", 51.5074, -0.1278, 118.99),
        ("Istanbul", 41.0082, 28.9784, 151.6),
        ("Jakarta", -6.2088, 106.8456, 295.15),
    ]

    func testSphericalMatchesPublishedBearings() {
        for ref in references {
            let r = QiblaCalculator.spherical(lat1: ref.lat, lon1: ref.lon, lat2: Kaaba.latitude, lon2: Kaaba.longitude)
            XCTAssertEqual(r.bearing, ref.bearing, accuracy: 0.1, ref.name)
        }
    }

    func testEllipsoidStaysCloseToSphere() {
        for ref in references {
            let ellipsoid = QiblaCalculator.qibla(latitude: ref.lat, longitude: ref.lon)
            let sphere = QiblaCalculator.spherical(lat1: ref.lat, lon1: ref.lon, lat2: Kaaba.latitude, lon2: Kaaba.longitude)
            XCTAssertLessThan(abs(QiblaCalculator.shortestDelta(from: sphere.bearing, to: ellipsoid.bearing)), 0.5, ref.name)
            XCTAssertEqual(ellipsoid.distance, sphere.distance, accuracy: sphere.distance * 0.005, ref.name)
        }
    }

    func testVincentyKnownDistance() {
        // Flinders Peak → Buninyong, the classic test case from Vincenty (1975): 54 972.271 m, azimuth 306°52'05.37".
        let r = QiblaCalculator.vincenty(
            lat1: -(37 + 57 / 60 + 3.72030 / 3600), lon1: 144 + 25 / 60 + 29.52440 / 3600,
            lat2: -(37 + 39 / 60 + 10.15610 / 3600), lon2: 143 + 55 / 60 + 35.38390 / 3600
        )
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.distance, 54_972.271, accuracy: 0.01)
        XCTAssertEqual(r!.bearing, 306 + 52 / 60 + 5.37 / 3600, accuracy: 1e-4)
    }

    func testAtKaabaIsZero() {
        let r = QiblaCalculator.qibla(from: Kaaba.coordinate)
        XCTAssertEqual(r.distance, 0)
    }

    func testNearAntipodeFallsBackGracefully() {
        let r = QiblaCalculator.qibla(latitude: -Kaaba.latitude + 0.001, longitude: Kaaba.longitude - 180)
        XCTAssertTrue(r.bearing.isFinite)
        XCTAssertGreaterThan(r.distance, 19_900_000)
    }

    func testNormalizedAndShortestDelta() {
        XCTAssertEqual(QiblaCalculator.normalized(-90), 270)
        XCTAssertEqual(QiblaCalculator.normalized(720), 0)
        XCTAssertEqual(QiblaCalculator.shortestDelta(from: 359, to: 1), 2)
        XCTAssertEqual(QiblaCalculator.shortestDelta(from: 1, to: 359), -2)
        XCTAssertEqual(QiblaCalculator.shortestDelta(from: 10, to: 100), 90)
    }
}

final class HeadingSmootherTests: XCTestCase {

    func testFirstSampleIsTakenAsIs() {
        var s = HeadingSmoother()
        XCTAssertEqual(s.update(42, at: Date()), 42)
    }

    func testSmoothsAcrossNorthTheShortWay() {
        var s = HeadingSmoother(timeConstant: 0.15)
        let t0 = Date()
        s.update(355, at: t0)
        let next = s.update(5, at: t0.addingTimeInterval(0.15))
        // Moved forward through 0°, not backwards through 180°.
        XCTAssertTrue(next > 355 || next < 5, "got \(next)")
        XCTAssertEqual(QiblaCalculator.shortestDelta(from: 355, to: next), 10 * (1 - exp(-1)), accuracy: 1e-6)
    }

    func testConvergesOverTime() {
        var s = HeadingSmoother(timeConstant: 0.15)
        let t0 = Date()
        s.update(0, at: t0)
        let settled = s.update(90, at: t0.addingTimeInterval(2))
        XCTAssertEqual(settled, 90, accuracy: 0.01)
    }

    func testResetForgetsHistory() {
        var s = HeadingSmoother()
        s.update(10, at: Date())
        s.reset()
        XCTAssertNil(s.value)
        XCTAssertEqual(s.update(200, at: Date()), 200)
    }
}

final class QiblaReadingTests: XCTestCase {

    func testRelativeDirectionAndTurn() {
        let r = QiblaReading(heading: 350, qiblaBearing: 10, distance: 0)
        XCTAssertEqual(r.relativeDirection, 20)
        XCTAssertEqual(r.turnAngle, 20)
        XCTAssertFalse(r.isFacingQibla())
        XCTAssertTrue(QiblaReading(heading: 151, qiblaBearing: 152, distance: 0).isFacingQibla())
    }
}

final class QiblaCompassViewTests: XCTestCase {

    func testUpdateDoesNotCrashAndWrapsShortWay() {
        let view = QiblaCompassView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        view.layoutIfNeeded()
        view.update(qiblaDirection: 350, heading: 359, animated: false)
        view.update(qiblaDirection: 5, heading: 2, animated: false)
        XCTAssertEqual(view.accessibilityValue, "5°")
    }
}
