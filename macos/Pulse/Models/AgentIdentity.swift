import Foundation

public struct AgentIdentity: Codable, Equatable, Sendable {
    public let agentID: String
    public let agentVersion: String
    public let hostname: String
    public let os: String
    public let kernelVersion: String
    public let architecture: String
    public let cpuCores: Int
    public let protocolVersion: Int

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case agentVersion = "agent_version"
        case hostname
        case os
        case kernelVersion = "kernel_version"
        case architecture
        case cpuCores = "cpu_cores"
        case protocolVersion = "protocol_version"
    }

    public init(
        agentID: String,
        agentVersion: String,
        hostname: String,
        os: String,
        kernelVersion: String = "unknown",
        architecture: String,
        cpuCores: Int = 1,
        protocolVersion: Int = 1
    ) {
        self.agentID = agentID
        self.agentVersion = agentVersion
        self.hostname = hostname
        self.os = os
        self.kernelVersion = kernelVersion
        self.architecture = architecture
        self.cpuCores = cpuCores
        self.protocolVersion = protocolVersion
    }
}
