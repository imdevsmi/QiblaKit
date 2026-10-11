import UIKit

/// A compass dial with a qibla needle.
///
/// The dial rotates with the device heading so N always points north; the needle points at the qibla.
/// Rotations always take the short way around, even across 0°/360°.
public final class QiblaCompassView: UIView {

    public struct Appearance {
        public var ringColor: UIColor
        public var innerRingColor: UIColor
        public var majorTickColor: UIColor
        public var minorTickColor: UIColor
        public var needleColor: UIColor
        public var needleTailColor: UIColor
        public var pivotFillColor: UIColor
        public var northLabelColor: UIColor
        public var cardinalLabelColor: UIColor
        /// North, east, south, west. Localize as needed (e.g. `["K", "D", "G", "B"]`).
        public var cardinalTitles: [String]

        public init(
            ringColor: UIColor = Appearance.dynamic(light: (0.325, 0.471, 0.380, 0.22), dark: (0.560, 0.737, 0.627, 0.45)),
            innerRingColor: UIColor = Appearance.dynamic(light: (0.325, 0.471, 0.380, 0.14), dark: (0.560, 0.737, 0.627, 0.28)),
            majorTickColor: UIColor = Appearance.dynamic(light: (0.325, 0.471, 0.380, 0.35), dark: (0.560, 0.737, 0.627, 0.75)),
            minorTickColor: UIColor = Appearance.dynamic(light: (0.325, 0.471, 0.380, 0.20), dark: (0.560, 0.737, 0.627, 0.45)),
            needleColor: UIColor = UIColor(red: 0.788, green: 0.635, blue: 0.153, alpha: 1),
            needleTailColor: UIColor = Appearance.dynamic(light: (0.29, 0.29, 0.29, 1), dark: (0.62, 0.62, 0.62, 1)),
            pivotFillColor: UIColor = .white,
            northLabelColor: UIColor = .label,
            cardinalLabelColor: UIColor = .secondaryLabel,
            cardinalTitles: [String] = ["N", "E", "S", "W"]
        ) {
            self.ringColor = ringColor
            self.innerRingColor = innerRingColor
            self.majorTickColor = majorTickColor
            self.minorTickColor = minorTickColor
            self.needleColor = needleColor
            self.needleTailColor = needleTailColor
            self.pivotFillColor = pivotFillColor
            self.northLabelColor = northLabelColor
            self.cardinalLabelColor = cardinalLabelColor
            self.cardinalTitles = cardinalTitles
        }

        public static let `default` = Appearance()

        public static func dynamic(
            light: (CGFloat, CGFloat, CGFloat, CGFloat),
            dark: (CGFloat, CGFloat, CGFloat, CGFloat)
        ) -> UIColor {
            UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
            }
        }
    }

    public var appearance: Appearance = .default {
        didSet { applyAppearance() }
    }

    /// Duration of each heading animation. Keep it short; headings arrive many times per second.
    public var animationDuration: CFTimeInterval = 0.1

    // MARK: - Layers & views

    private let dialContainer = UIView()
    private let ringLayer = CAShapeLayer()
    private let innerRingLayer = CAShapeLayer()
    private let majorTicksLayer = CAShapeLayer()
    private let minorTicksLayer = CAShapeLayer()
    private let cardinalLabels = (0..<4).map { _ in UILabel() }

    private let needleContainer = UIView()
    private let pointerLayer = CAShapeLayer()
    private let tailLayer = CAShapeLayer()
    private let pivotView = UIView()

    /// Unwrapped (cumulative) angles in radians, so animations never spin the long way.
    private var headingAngle: CGFloat = 0
    private var needleAngle: CGFloat = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Update

    /// Updates the dial and needle from a provider reading.
    public func update(with reading: QiblaReading, animated: Bool = true) {
        update(qiblaDirection: reading.relativeDirection, heading: reading.heading, animated: animated)
    }

    /// - Parameters:
    ///   - qiblaDirection: Qibla relative to the top of the device, degrees (see `QiblaReading.relativeDirection`).
    ///   - heading: Device true heading, degrees.
    public func update(qiblaDirection: Double, heading: Double, animated: Bool = true) {
        let headingDelta = CGFloat(QiblaCalculator.shortestDelta(from: Double(headingAngle).degrees, to: heading).radians)
        let needleDelta = CGFloat(QiblaCalculator.shortestDelta(from: Double(needleAngle).degrees, to: qiblaDirection).radians)
        headingAngle += headingDelta
        needleAngle += needleDelta

        rotate(dialContainer.layer, to: -headingAngle, delta: -headingDelta, animated: animated)
        rotate(needleContainer.layer, to: needleAngle, delta: needleDelta, animated: animated)
        // Keep the letters upright.
        for label in cardinalLabels {
            rotate(label.layer, to: headingAngle, delta: headingDelta, animated: animated)
        }

        accessibilityValue = String(format: "%.0f°", QiblaCalculator.normalized(qiblaDirection))
    }

    /// Sets the model value and adds an additive animation from the previous angle.
    /// Additive animations blend smoothly when updates arrive faster than they finish.
    private func rotate(_ layer: CALayer, to angle: CGFloat, delta: CGFloat, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(angle, forKeyPath: "transform.rotation.z")
        CATransaction.commit()

        guard animated, delta != 0, animationDuration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = -delta
        animation.toValue = 0
        animation.isAdditive = true
        animation.duration = animationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: nil)
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let size = min(bounds.width, bounds.height)
        let local = CGRect(x: 0, y: 0, width: size, height: size)
        let c = CGPoint(x: local.midX, y: local.midY)
        let radius = size / 2

        for container in [dialContainer, needleContainer] {
            container.bounds = local
            container.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }

        ringLayer.path = circle(center: c, radius: radius * 0.83)
        innerRingLayer.path = circle(center: c, radius: radius * 0.63)

        let majorPath = UIBezierPath()
        for angle in stride(from: 0, to: 360, by: 90) {
            appendTick(to: majorPath, center: c, radius: radius, degrees: CGFloat(angle), from: 0.86, to: 0.93)
        }
        majorTicksLayer.path = majorPath.cgPath

        let minorPath = UIBezierPath()
        for angle in stride(from: 30, to: 360, by: 30) where angle % 90 != 0 {
            appendTick(to: minorPath, center: c, radius: radius, degrees: CGFloat(angle), from: 0.87, to: 0.93)
        }
        minorTicksLayer.path = minorPath.cgPath

        let pointer = UIBezierPath()
        pointer.move(to: CGPoint(x: c.x - 4, y: c.y))
        pointer.addLine(to: CGPoint(x: c.x, y: c.y - radius * 0.58))
        pointer.addLine(to: CGPoint(x: c.x + 4, y: c.y))
        pointer.close()
        pointerLayer.path = pointer.cgPath

        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: c.x - 3, y: c.y))
        tail.addLine(to: CGPoint(x: c.x, y: c.y + radius * 0.25))
        tail.addLine(to: CGPoint(x: c.x + 3, y: c.y))
        tail.close()
        tailLayer.path = tail.cgPath

        let pivotSize: CGFloat = 16
        pivotView.bounds = CGRect(x: 0, y: 0, width: pivotSize, height: pivotSize)
        pivotView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pivotView.layer.cornerRadius = pivotSize / 2

        // Labels are placed with bounds/center so their own rotation does not disturb layout.
        let labelRadius = radius - 14
        for (index, label) in cardinalLabels.enumerated() {
            let angle = CGFloat(index) * .pi / 2 - .pi / 2
            label.bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
            label.center = CGPoint(x: c.x + labelRadius * cos(angle), y: c.y + labelRadius * sin(angle))
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyAppearance()
        }
    }
}

// MARK: - Private

private extension QiblaCompassView {

    func setup() {
        backgroundColor = .clear
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityLabel = "Qibla compass"

        addSubview(dialContainer)
        dialContainer.isUserInteractionEnabled = false
        [ringLayer, innerRingLayer, majorTicksLayer, minorTicksLayer].forEach {
            $0.fillColor = UIColor.clear.cgColor
            $0.lineCap = .round
            dialContainer.layer.addSublayer($0)
        }
        ringLayer.lineWidth = 2
        innerRingLayer.lineWidth = 1
        majorTicksLayer.lineWidth = 2
        minorTicksLayer.lineWidth = 1.5

        for (index, label) in cardinalLabels.enumerated() {
            label.textAlignment = .center
            label.font = .systemFont(ofSize: index == 0 ? 16 : 15, weight: index == 0 ? .bold : .semibold)
            dialContainer.addSubview(label)
        }

        addSubview(needleContainer)
        needleContainer.isUserInteractionEnabled = false
        needleContainer.layer.addSublayer(pointerLayer)
        needleContainer.layer.addSublayer(tailLayer)

        pivotView.layer.borderWidth = 2.5
        pivotView.isUserInteractionEnabled = false
        addSubview(pivotView)

        applyAppearance()
    }

    func applyAppearance() {
        let a = appearance
        let traits = traitCollection
        ringLayer.strokeColor = a.ringColor.resolvedColor(with: traits).cgColor
        innerRingLayer.strokeColor = a.innerRingColor.resolvedColor(with: traits).cgColor
        majorTicksLayer.strokeColor = a.majorTickColor.resolvedColor(with: traits).cgColor
        minorTicksLayer.strokeColor = a.minorTickColor.resolvedColor(with: traits).cgColor
        pointerLayer.fillColor = a.needleColor.resolvedColor(with: traits).cgColor
        tailLayer.fillColor = a.needleTailColor.resolvedColor(with: traits).cgColor
        pivotView.backgroundColor = a.pivotFillColor
        pivotView.layer.borderColor = a.needleColor.resolvedColor(with: traits).cgColor

        for (index, label) in cardinalLabels.enumerated() {
            label.text = index < a.cardinalTitles.count ? a.cardinalTitles[index] : nil
            label.textColor = index == 0 ? a.northLabelColor : a.cardinalLabelColor
        }
    }

    func circle(center: CGPoint, radius: CGFloat) -> CGPath {
        UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
    }

    func appendTick(to path: UIBezierPath, center: CGPoint, radius: CGFloat, degrees: CGFloat, from: CGFloat, to: CGFloat) {
        let angle = (degrees - 90) * .pi / 180
        path.move(to: CGPoint(x: center.x + radius * from * cos(angle), y: center.y + radius * from * sin(angle)))
        path.addLine(to: CGPoint(x: center.x + radius * to * cos(angle), y: center.y + radius * to * sin(angle)))
    }
}
