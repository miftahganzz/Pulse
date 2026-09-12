import Foundation

public protocol PulseAgentClientDelegate: AnyObject, Sendable {
    func client(_ client: PulseAgentClient, didUpdateState state: ConnectionState)
    func client(_ client: PulseAgentClient, didReceiveIdentity identity: AgentIdentity)
    func client(_ client: PulseAgentClient, didReceiveHeartbeat heartbeat: HeartbeatPayload)
    func client(_ client: PulseAgentClient, didReceiveMetrics metrics: MetricsSnapshot)
    func client(_ client: PulseAgentClient, didFailWithError error: Error)
}

public final class PulseAgentClient: NSObject, @unchecked Sendable {
    public let host: String
    public let port: Int
    public let token: String

    public weak var delegate: PulseAgentClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private var reconnectionPolicy = ReconnectionPolicy()
    private var isUserInitiatedDisconnect = false

    private var heartbeatTimer: Timer?
    private var lastHeartbeatReceivedAt: Date?
    private let heartbeatTimeoutInterval: TimeInterval = 15.0

    private let queue = DispatchQueue(label: "com.pulse.client", qos: .userInitiated)

    public init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config, delegate: PinnedURLSessionDelegate(), delegateQueue: nil)
    }

    public func connect() {
        queue.async {
            self.isUserInitiatedDisconnect = false
            self.reconnectionPolicy.reset()
            self.startConnection()
        }
    }

    public func disconnect() {
        queue.async {
            self.isUserInitiatedDisconnect = true
            self.cleanupConnection()
            self.delegate?.client(self, didUpdateState: .disconnected)
        }
    }

    public func fetchProcesses(limit: Int = 30, sortBy: String = "cpu", completion: @escaping @Sendable (Result<[ProcessItem], Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/processes?limit=\(limit)&sort=\(sortBy)") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let env = try JSONDecoder().decode(ProtocolEnvelope<ProcessesSnapshot>.self, from: data)
                completion(.success(env.payload.processes))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func fetchServices(completion: @escaping @Sendable (Result<[SystemServiceItem], Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/services") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let env = try JSONDecoder().decode(ProtocolEnvelope<ServicesSnapshot>.self, from: data)
                completion(.success(env.payload.services))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func fetchSecurityPorts(completion: @escaping @Sendable (Result<SecuritySnapshot, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/security/ports") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let env = try JSONDecoder().decode(ProtocolEnvelope<SecuritySnapshot>.self, from: data)
                completion(.success(env.payload))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func killProcess(pid: Int, signal: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/processes/\(pid)/kill") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["signal": signal]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(PulseClientError.httpError(statusCode: 500)))
                return
            }
            guard httpResponse.statusCode == 200 else {
                let errMsg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(PulseClientError.generic(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))))
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String {
                completion(.success(msg))
            } else {
                completion(.success("Process \(pid) signaled with \(signal)"))
            }
        }.resume()
    }

    public func controlService(name: String, action: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/services/\(name)/action") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["action": action]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(PulseClientError.httpError(statusCode: 500)))
                return
            }
            guard httpResponse.statusCode == 200 else {
                let errMsg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(PulseClientError.generic(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))))
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String {
                completion(.success(msg))
            } else {
                completion(.success("Service \(name) action \(action) succeeded"))
            }
        }.resume()
    }

    public func fetchDockerContainers(completion: @escaping @Sendable (Result<DockerStatusResponse, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/docker/containers") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let status = try JSONDecoder().decode(DockerStatusResponse.self, from: data)
                completion(.success(status))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func controlDockerContainer(id: String, action: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/docker/containers/\(id)/action") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["action": action]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(PulseClientError.httpError(statusCode: 500)))
                return
            }
            guard httpResponse.statusCode == 200 else {
                let errMsg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(PulseClientError.generic(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))))
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String {
                completion(.success(msg))
            } else {
                completion(.success("Container \(id) action \(action) succeeded"))
            }
        }.resume()
    }

    public func fetchDockerLogs(id: String, tail: Int = 100, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/docker/containers/\(id)/logs?tail=\(tail)") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let res = try JSONDecoder().decode(DockerLogsResponse.self, from: data)
                completion(.success(res.logs))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func fetchDiscovery(completion: @escaping @Sendable (Result<DiscoveryResultPayload, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/discovery") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let res = try decoder.decode(DiscoveryResultPayload.self, from: data)
                completion(.success(res))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func checkMonitorsHealth(monitors: [MonitorHealthCheckRequest], completion: @escaping @Sendable (Result<[HealthCheckResultItem], Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/monitors/health") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(monitors)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let results = try decoder.decode([HealthCheckResultItem].self, from: data)
                completion(.success(results))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func executeAction(action: String, target: String, timeoutSeconds: Int = 30, completion: @escaping @Sendable (Result<ActionResultPayload, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/actions/execute") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ActionRequestPayload(action: action, target: target, timeoutSeconds: timeoutSeconds)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let result = try decoder.decode(ActionResultPayload.self, from: data)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func probeDatabase(config: DatabaseProbeRequest, completion: @escaping @Sendable (Result<DatabaseProbeResponse, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/monitors/probe-db") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(config)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let res = try decoder.decode(DatabaseProbeResponse.self, from: data)
                completion(.success(res))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func startConnection() {
        guard !isUserInitiatedDisconnect else { return }


        delegate?.client(self, didUpdateState: .connecting)
        PulseLog.network.info("Connecting to agent at \(self.host):\(self.port)")

        testInfoEndpoint { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard !self.isUserInitiatedDisconnect else { return }

                switch result {
                case .success(let identity):
                    self.delegate?.client(self, didReceiveIdentity: identity)
                    self.openWebSocketStream()
                case .failure(let error):
                    PulseLog.network.error("Connection probe failed: \(error.localizedDescription)")
                    self.delegate?.client(self, didFailWithError: error)
                    self.scheduleReconnection()
                }
            }
        }
    }

    public func fetchIdentity(completion: @escaping @Sendable (Result<AgentIdentity, Error>) -> Void) {
        testInfoEndpoint(completion: completion)
    }

    private func testInfoEndpoint(completion: @escaping @Sendable (Result<AgentIdentity, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/info") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            if httpResponse.statusCode == 401 {
                completion(.failure(PulseClientError.unauthorized))
                return
            }

            guard httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: httpResponse.statusCode)))
                return
            }

            do {
                let envelope = try JSONDecoder().decode(ProtocolEnvelope<AgentIdentity>.self, from: data)
                completion(.success(envelope.payload))
            } catch {
                PulseLog.network.error("JSON decode error: \(error.localizedDescription)")
                completion(.failure(PulseClientError.protocolMismatch))
            }
        }
        task.resume()
    }

    public static func pairWithCode(host: String, port: Int, pairCode: String, completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/pair") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["pair_code": pairCode]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default, delegate: PinnedURLSessionDelegate(), delegateQueue: nil)
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(PulseClientError.httpError(statusCode: 500)))
                return
            }
            guard httpResponse.statusCode == 200, let data = data else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(PulseClientError.generic(msg.trimmingCharacters(in: .whitespacesAndNewlines))))
                return
            }
            do {
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(dict))
                } else {
                    completion(.failure(PulseClientError.protocolMismatch))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func openWebSocketStream() {
        guard let url = URL(string: "wss://\(host):\(port)/ws/v1/stream?token=\(token)") else {
            scheduleReconnection()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        reconnectionPolicy.reset()
        delegate?.client(self, didUpdateState: .connected)
        PulseLog.network.info("WebSocket connected to \(self.host):\(self.port)")

        startHeartbeatMonitor()
        listenForMessages()
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            self.queue.async {
                guard !self.isUserInitiatedDisconnect else { return }

                switch result {
                case .success(let message):
                    self.handleWebSocketMessage(message)
                    self.listenForMessages()
                case .failure(let error):
                    PulseLog.network.warn("WebSocket disconnected: \(error.localizedDescription)")
                    self.handleConnectionLoss()
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let type = json?["type"] as? String else { return }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                if let date = ISO8601DateFormatter().date(from: string) {
                    return date
                }
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = f.date(from: string) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
            }

            switch type {
            case "agent.hello":
                let env = try decoder.decode(ProtocolEnvelope<AgentIdentity>.self, from: data)
                delegate?.client(self, didReceiveIdentity: env.payload)

            case "agent.heartbeat":
                let env = try decoder.decode(ProtocolEnvelope<HeartbeatPayload>.self, from: data)
                lastHeartbeatReceivedAt = Date()
                delegate?.client(self, didReceiveHeartbeat: env.payload)

            case "metrics.snapshot":
                let env = try decoder.decode(ProtocolEnvelope<MetricsSnapshot>.self, from: data)
                lastHeartbeatReceivedAt = Date()
                delegate?.client(self, didReceiveMetrics: env.payload)

            default:
                PulseLog.network.debug("Ignored unhandled message type: \(type)")
            }
        } catch {
            PulseLog.network.error("Error decoding message: \(error.localizedDescription)")
        }
    }

    private func startHeartbeatMonitor() {
        lastHeartbeatReceivedAt = Date()
        DispatchQueue.main.async {
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkHeartbeatLiveness()
            }
        }
    }

    private func checkHeartbeatLiveness() {
        queue.async {
            guard !self.isUserInitiatedDisconnect, let last = self.lastHeartbeatReceivedAt else { return }
            if Date().timeIntervalSince(last) > self.heartbeatTimeoutInterval {
                PulseLog.network.warn("Heartbeat timeout exceeded (\(self.heartbeatTimeoutInterval)s). Triggering reconnection.")
                self.handleConnectionLoss()
            }
        }
    }

    private func handleConnectionLoss() {
        cleanupConnection()
        scheduleReconnection()
    }

    private func scheduleReconnection() {
        guard !isUserInitiatedDisconnect else { return }

        let delay = reconnectionPolicy.nextInterval()
        let attempt = reconnectionPolicy.attempt

        delegate?.client(self, didUpdateState: .reconnecting(attempt: attempt, nextRetrySeconds: Int(delay)))
        PulseLog.network.info("Scheduling reconnect attempt \(attempt) in \(delay)s")

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isUserInitiatedDisconnect else { return }
            self.startConnection()
        }
    }

    public func fetchSuggestedDependencies(completion: @escaping @Sendable (Result<[SuggestedDependencyDTO], Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/intelligence/suggested-dependencies") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                struct SuggestionsResponse: Decodable {
                    let suggestions: [SuggestedDependencyDTO]
                }
                let res = try JSONDecoder().decode(SuggestionsResponse.self, from: data)
                completion(.success(res.suggestions))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func streamLogs(
        type: String,
        target: String,
        tail: Int = 100,
        onConnected: (@Sendable () -> Void)? = nil,
        onLine: @escaping @Sendable (LogEntryMessage) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> URLSessionWebSocketTask? {
        guard let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "wss://\(host):\(port)/ws/v1/logs?type=\(type)&target=\(encodedTarget)&tail=\(tail)&follow=true") else {
            onError(URLError(.badURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        task.resume()

        task.sendPing { error in
            if let error = error {
                if !Self.isCancellation(error) {
                    onError(error)
                }
            } else {
                onConnected?()
            }
        }

        @Sendable func readNext() {
            task.receive { result in
                switch result {
                case .success(let msg):
                    switch msg {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let entry = try? JSONDecoder().decode(LogEntryMessage.self, from: data) {
                            onLine(entry)
                        }
                    case .data(let data):
                        if let entry = try? JSONDecoder().decode(LogEntryMessage.self, from: data) {
                            onLine(entry)
                        }
                    @unknown default:
                        break
                    }
                    readNext()
                case .failure(let err):
                    if !Self.isCancellation(err) {
                        onError(err)
                    }
                }
            }
        }

        readNext()
        return task
    }

    public func fetchStorageAnalysis(completion: @escaping @Sendable (Result<StorageAnalysis, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/storage/analyze") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            do {
                let analysis = try JSONDecoder().decode(StorageAnalysis.self, from: data)
                completion(.success(analysis))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func testTelegram(botToken: String, chatID: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/alerts/telegram/test") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload = ["bot_token": botToken, "chat_id": chatID]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(PulseClientError.generic("No response from agent")))
                return
            }
            if httpResponse.statusCode == 200 {
                completion(.success("Test alert sent successfully!"))
            } else {
                var errDetail = "HTTP \(httpResponse.statusCode)"
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let msg = json["error"] as? String {
                    errDetail = msg
                }
                completion(.failure(PulseClientError.generic(errDetail)))
            }
        }.resume()
    }

    public func updateTelegramConfig(_ config: TelegramConfig, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "https://\(host):\(port)/api/v1/alerts/telegram/config") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(config)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(.failure(PulseClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)))
                return
            }
            completion(.success(()))
        }.resume()
    }

    private func cleanupConnection() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsErr = error as NSError
        if nsErr.code == NSURLErrorCancelled { return true }
        if nsErr.domain == NSPOSIXErrorDomain && nsErr.code == 89 { return true }
        if nsErr.domain == "kCFErrorDomainCFNetwork" && nsErr.code == -999 { return true }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cancelled") || desc.contains("canceled") { return true }
        return false
    }
}

public enum PulseClientError: LocalizedError {
    case unauthorized
    case httpError(statusCode: Int)
    case protocolMismatch
    case generic(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication failed: invalid or expired agent token"
        case .httpError(let code):
            return "Agent server error (HTTP \(code))"
        case .protocolMismatch:
            return "Protocol mismatch: agent sent unexpected payload format"
        case .generic(let msg):
            return msg
        }
    }
}
