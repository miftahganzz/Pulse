import Foundation

public final class TelegramAlertService: ObservableObject, @unchecked Sendable {
    public static let shared = TelegramAlertService()

    private let userDefaultsKey = "com.pulse.telegram.config"
    @Published public var config: TelegramConfig

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(TelegramConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = TelegramConfig()
        }
    }

    public func updateConfig(_ newConfig: TelegramConfig) {
        DispatchQueue.main.async {
            self.config = newConfig
            if let data = try? JSONEncoder().encode(newConfig) {
                UserDefaults.standard.set(data, forKey: self.userDefaultsKey)
            }
        }
    }

    public func sendAlert(title: String, body: String, serverName: String, isCritical: Bool = false) {
        let currentConfig = config
        guard currentConfig.enabled, !currentConfig.botToken.isEmpty, !currentConfig.chatIDs.isEmpty else {
            return
        }

        let icon = isCritical ? "🚨" : "⚠️"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(icon) *[PULSE ALERT]*\n*Server:* `\(serverName)`\n*Alert:* *\(title)*\n*Details:* \(body)\n*Time:* `\(timestamp)`"

        for chatID in currentConfig.chatIDs {
            sendMessage(token: currentConfig.botToken, chatID: chatID, text: text)
        }
    }

    public func sendTestMessage(token: String, chatID: String) async throws -> String {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanToken.isEmpty else {
            throw PulseClientError.generic("Telegram Bot Token cannot be empty")
        }
        guard !cleanChatID.isEmpty else {
            throw PulseClientError.generic("Telegram Chat ID cannot be empty")
        }

        let testText = "✅ *Pulse Alert Test*\nSuccessfully connected Telegram Bot to Pulse!\n*Time:* `\(ISO8601DateFormatter().string(from: Date()))`"
        try await sendMessageAsync(token: cleanToken, chatID: cleanChatID, text: testText)
        return "Test alert delivered successfully to \(cleanChatID)"
    }

    private func sendMessage(token: String, chatID: String, text: String) {
        Task {
            try? await sendMessageAsync(token: token, chatID: chatID, text: text)
        }
    }

    private func sendMessageAsync(token: String, chatID: String, text: String) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw PulseClientError.generic("Invalid Telegram API URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "chat_id": chatID,
            "text": text,
            "parse_mode": "Markdown"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PulseClientError.generic("No response from Telegram API")
        }

        if httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let desc = json["description"] as? String {
                throw PulseClientError.generic("Telegram error: \(desc)")
            }
            throw PulseClientError.generic("Telegram API returned HTTP \(httpResponse.statusCode)")
        }
    }
}
