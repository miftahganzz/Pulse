import Foundation

public struct ReconnectionPolicy: Sendable {
    public let backoffIntervals: [TimeInterval]
    private(set) var currentAttempt: Int = 0

    public init(backoffIntervals: [TimeInterval] = [1.0, 2.0, 5.0, 10.0, 30.0]) {
        self.backoffIntervals = backoffIntervals
    }

    public mutating func nextInterval() -> TimeInterval {
        let index = min(currentAttempt, backoffIntervals.count - 1)
        let interval = backoffIntervals[index]
        currentAttempt += 1
        return interval
    }

    public mutating func reset() {
        currentAttempt = 0
    }

    public var attempt: Int {
        currentAttempt
    }
}
