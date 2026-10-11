import CoreLocation

/// A single compass update.
public struct QiblaReading: Equatable {
    /// Smoothed true heading of the device, degrees clockwise from true north.
    public let heading: Double
    /// Qibla bearing from the current location, degrees clockwise from true north.
    public let qiblaBearing: Double
    /// Distance to the Kaaba in meters.
    public let distance: Double

    /// Where the qibla is relative to the top of the device, 0..<360.
    /// Rotate a needle by this angle to point at the qibla.
    public var relativeDirection: Double {
        QiblaCalculator.normalized(qiblaBearing - heading)
    }

    /// Signed turn needed to face the qibla, -180...180 (positive = turn right).
    public var turnAngle: Double {
        QiblaCalculator.shortestDelta(from: heading, to: qiblaBearing)
    }

    /// True if the device points at the qibla within `tolerance` degrees.
    public func isFacingQibla(tolerance: Double = 3) -> Bool {
        abs(turnAngle) <= tolerance
    }
}

public enum QiblaError: Error {
    /// Location permission was denied or is restricted.
    case permissionDenied
    /// This device has no magnetometer.
    case headingUnavailable
    /// Core Location reported an error.
    case location(Error)
}

public protocol QiblaHeadingProviderDelegate: AnyObject {
    /// A new location was used to compute the qibla.
    func qiblaProvider(_ provider: QiblaHeadingProvider, didUpdateLocation location: CLLocation, qibla: QiblaCalculator.Result)
    /// The smoothed heading changed by more than `reportThreshold`.
    func qiblaProvider(_ provider: QiblaHeadingProvider, didUpdate reading: QiblaReading)
    /// Heading accuracy crossed `calibrationThreshold`. Show a "move your phone in a figure 8" hint.
    func qiblaProvider(_ provider: QiblaHeadingProvider, didChangeCalibrationNeeded needsCalibration: Bool)
    func qiblaProvider(_ provider: QiblaHeadingProvider, didFailWith error: QiblaError)
}

public extension QiblaHeadingProviderDelegate {
    func qiblaProvider(_ provider: QiblaHeadingProvider, didUpdateLocation location: CLLocation, qibla: QiblaCalculator.Result) {}
    func qiblaProvider(_ provider: QiblaHeadingProvider, didChangeCalibrationNeeded needsCalibration: Bool) {}
    func qiblaProvider(_ provider: QiblaHeadingProvider, didFailWith error: QiblaError) {}
}

/// Combines location and compass updates into smoothed qibla readings.
///
/// Create it on the main thread; delegate callbacks are delivered there.
public final class QiblaHeadingProvider: NSObject {

    public weak var delegate: QiblaHeadingProviderDelegate?

    /// Smoothing time constant in seconds.
    public var smoothingTimeConstant: TimeInterval {
        get { smoother.timeConstant }
        set { smoother.timeConstant = newValue }
    }

    /// Heading changes smaller than this (degrees) are not reported, to avoid needless redraws.
    public var reportThreshold: Double = 0.1

    /// `headingAccuracy` above this (degrees) is reported as needing calibration.
    public var calibrationThreshold: Double = 20

    /// Whether iOS may show its own calibration screen.
    public var showsSystemCalibration = true

    /// Device orientation used for headings. Defaults to `.portrait`.
    public var headingOrientation: CLDeviceOrientation {
        get { locationManager.headingOrientation }
        set { locationManager.headingOrientation = newValue }
    }

    /// When set, this location is used instead of GPS (e.g. a searched city).
    /// Set to nil to go back to the device location.
    public var manualLocation: CLLocation? {
        didSet {
            if let manualLocation {
                locationManager.stopUpdatingLocation()
                use(manualLocation)
            } else if isRunning {
                locationManager.startUpdatingLocation()
            }
        }
    }

    /// The qibla for the location in use, if known.
    public private(set) var qibla: QiblaCalculator.Result?
    public private(set) var needsCalibration = false

    private let locationManager = CLLocationManager()
    private var smoother = HeadingSmoother()
    private var lastReportedHeading: Double?
    private var isRunning = false

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.distanceFilter = 100
        // No filter: keep receiving samples when the phone is still, so the needle settles exactly.
        locationManager.headingFilter = kCLHeadingFilterNone
        locationManager.headingOrientation = .portrait
    }

    /// Requests permission if needed and starts location and heading updates.
    public func start() {
        isRunning = true
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            delegate?.qiblaProvider(self, didFailWith: .permissionDenied)
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        @unknown default:
            break
        }
    }

    public func stop() {
        isRunning = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        smoother.reset()
        lastReportedHeading = nil
    }

    private func beginUpdates() {
        if let manualLocation {
            use(manualLocation)
        } else {
            if let last = locationManager.location { use(last) }
            locationManager.startUpdatingLocation()
        }
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        } else {
            delegate?.qiblaProvider(self, didFailWith: .headingUnavailable)
        }
    }

    private func use(_ location: CLLocation) {
        let result = QiblaCalculator.qibla(from: location.coordinate)
        qibla = result
        // Location changed: report on the next heading even if the phone has not moved.
        lastReportedHeading = nil
        delegate?.qiblaProvider(self, didUpdateLocation: location, qibla: result)
    }
}

// MARK: - CLLocationManagerDelegate

extension QiblaHeadingProvider: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        case .denied, .restricted:
            delegate?.qiblaProvider(self, didFailWith: .permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manualLocation == nil, let location = locations.last else { return }
        use(location)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let poor = newHeading.headingAccuracy < 0 || newHeading.headingAccuracy > calibrationThreshold
        if poor != needsCalibration {
            needsCalibration = poor
            delegate?.qiblaProvider(self, didChangeCalibrationNeeded: poor)
        }

        guard newHeading.headingAccuracy >= 0, newHeading.trueHeading >= 0, let qibla else { return }

        let heading = smoother.update(newHeading.trueHeading, at: newHeading.timestamp)

        if let last = lastReportedHeading,
           abs(QiblaCalculator.shortestDelta(from: last, to: heading)) < reportThreshold { return }
        lastReportedHeading = heading

        let reading = QiblaReading(heading: heading, qiblaBearing: qibla.bearing, distance: qibla.distance)
        delegate?.qiblaProvider(self, didUpdate: reading)
    }

    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        showsSystemCalibration
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient: Core Location keeps trying.
        if (error as? CLError)?.code == .locationUnknown { return }
        delegate?.qiblaProvider(self, didFailWith: .location(error))
    }
}
