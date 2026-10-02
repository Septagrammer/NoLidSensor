import Foundation

public enum SleepPolicy {
    public static func eligible(enabled: Bool, now: Date, snoozedUntil: Date, idle: Double, requiredIdle: Double) -> Bool {
        enabled && now >= snoozedUntil && idle.isFinite && idle >= requiredIdle
    }
    public static func dark(_ samples: [Double], threshold: Double) -> Bool {
        samples.count >= 5 && samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= threshold }
    }
    public static func unchangedActivity(idleBefore: Double, idleAfter: Double, elapsed: Double) -> Bool {
        idleAfter >= idleBefore + elapsed - 0.5
    }
}

// A fresh window requires two scheduled checks. Uptime avoids wall-clock jumps.
public struct ActivityWindow {
    private var previousCheck: Double?
    private var windowStart: Double?
    public init() {}
    public mutating func beginCheck(at uptime: Double) -> Bool {
        windowStart = previousCheck
        previousCheck = uptime
        return windowStart != nil
    }
    public func requiredIdle(at uptime: Double) -> Double {
        guard let start = windowStart, uptime >= start else { return .infinity }
        return uptime - start
    }
}

public enum EventSchedule {
    // Only the visible sleep prompt needs one-second updates.
    public static func delay(enabled: Bool, suspended: Bool, checking: Bool, prompt: Bool,
                             snoozeRemaining: Double, checkRemaining: Double) -> Double? {
        guard !suspended else { return nil }
        if snoozeRemaining > 0 { return snoozeRemaining }
        guard enabled, !checking else { return nil }
        return prompt ? 1 : max(0.01, checkRemaining)
    }
}
