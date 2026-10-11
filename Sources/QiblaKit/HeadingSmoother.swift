import Foundation

/// Time-based exponential smoothing for compass headings.
///
/// `alpha = 1 - e^(-dt/τ)` depends on elapsed time rather than on the number of updates,
/// so the needle responds the same on devices with different sensor rates.
/// Wraps correctly across 0°/360°.
public struct HeadingSmoother {

    /// Smoothing time constant in seconds. Larger = calmer but slower needle.
    public var timeConstant: TimeInterval

    /// The current smoothed heading (0..<360), or nil before the first sample.
    public private(set) var value: Double?

    private var lastTimestamp: Date?

    public init(timeConstant: TimeInterval = 0.15) {
        self.timeConstant = timeConstant
    }

    /// Feeds a raw heading (degrees) and returns the smoothed heading.
    @discardableResult
    public mutating func update(_ heading: Double, at timestamp: Date) -> Double {
        defer { lastTimestamp = timestamp }

        guard let current = value else {
            let first = QiblaCalculator.normalized(heading)
            value = first
            return first
        }

        let dt = lastTimestamp.map { timestamp.timeIntervalSince($0) } ?? 0
        let alpha = (dt > 0 && timeConstant > 0) ? 1 - exp(-dt / timeConstant) : 1
        let next = QiblaCalculator.normalized(current + QiblaCalculator.shortestDelta(from: current, to: heading) * alpha)
        value = next
        return next
    }

    public mutating func reset() {
        value = nil
        lastTimestamp = nil
    }
}
