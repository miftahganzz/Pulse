import Foundation
import os

enum PulseLog {
    private static let subsystem = "com.pulse.app"

    static let network = Logger(subsystem: subsystem, category: "pulse.network")
    static let agent = Logger(subsystem: subsystem, category: "pulse.agent")
    static let security = Logger(subsystem: subsystem, category: "pulse.security")
    static let persistence = Logger(subsystem: subsystem, category: "pulse.persistence")
    static let ui = Logger(subsystem: subsystem, category: "pulse.ui")
}

extension Logger {
    func warn(_ message: String) {
        self.warning("\(message, privacy: .public)")
    }
}
