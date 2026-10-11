# QiblaKit

Accurate qibla direction and a smooth, ready-made qibla compass for UIKit apps.

- **Ellipsoidal math** — bearing and distance to the Kaaba on the WGS84 ellipsoid (Vincenty), the same Earth model GPS uses. Falls back to the great-circle solution near the antipode.
- **Calm, responsive needle** — time-based exponential smoothing of compass headings that behaves the same on every device's sensor rate and never jumps across north.
- **Calibration signal** — tells you when heading accuracy is poor so you can show a "figure 8" hint.
- **Drop-in compass view** — themeable `QiblaCompassView` with dark mode support; rotations always take the short way around.
- **Manual location** — compute the qibla for a searched city instead of GPS.
- No dependencies.

## Requirements

- iOS 14+
- Swift 5.9+

## Installation

In Xcode: **File ▸ Add Package Dependencies…** and enter:

```
https://github.com/imdevsmi/QiblaKit.git
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/imdevsmi/QiblaKit.git", from: "1.0.0")
]
```

Add `NSLocationWhenInUseUsageDescription` to your Info.plist.

## Usage

### Just the math

```swift
import QiblaKit

let qibla = QiblaCalculator.qibla(latitude: 41.0082, longitude: 28.9784) // Istanbul
qibla.bearing   // ≈ 151.6° clockwise from true north
qibla.distance  // ≈ 2 400 000 m
```

### Live compass

```swift
import QiblaKit

final class QiblaViewController: UIViewController, QiblaHeadingProviderDelegate {

    private let provider = QiblaHeadingProvider()
    private let compass = QiblaCompassView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(compass)
        // ...layout the compass (it draws a circle in the largest centered square)
        provider.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        provider.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        provider.stop()
    }

    func qiblaProvider(_ provider: QiblaHeadingProvider, didUpdate reading: QiblaReading) {
        compass.update(with: reading)

        if reading.isFacingQibla(tolerance: 3) {
            // e.g. play a haptic
        }
    }

    func qiblaProvider(_ provider: QiblaHeadingProvider, didChangeCalibrationNeeded needsCalibration: Bool) {
        // show / hide a "move your phone in a figure 8" hint
    }

    func qiblaProvider(_ provider: QiblaHeadingProvider, didFailWith error: QiblaError) {
        // .permissionDenied, .headingUnavailable, .location(Error)
    }
}
```

### Searched location

```swift
provider.manualLocation = CLLocation(latitude: 51.5074, longitude: -0.1278)
provider.manualLocation = nil // back to GPS
```

### Tuning

```swift
provider.smoothingTimeConstant = 0.15 // seconds; larger = calmer, slower
provider.reportThreshold = 0.1        // degrees; smaller changes are not reported
provider.calibrationThreshold = 20    // degrees of heading accuracy
```

### Appearance

```swift
compass.appearance = .init(
    needleColor: .systemGreen,
    cardinalTitles: ["K", "D", "G", "B"] // localized N / E / S / W
)
```

## License

QiblaKit is available under the MIT license. See [LICENSE](LICENSE) for details.
