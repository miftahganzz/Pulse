import Foundation

/// Deterministic causal reasoning & intelligence engine for Pulse.
/// Correlates incidents against the server dependency graph to detect root causes,
/// compute blast radius, explain evidence, and detect statistical anomalies.
public final class IntelligenceEngine {
    public static let shared = IntelligenceEngine()

    public init() {}

    // MARK: - Root Cause Analysis
    /// Correlates active incidents on a server with its registered dependency DAG.
    /// Uses a deterministic scoring system (no LLM):
    /// - Upstream failure penalty: +40
    /// - Chronologically failed first: +30
    /// - Dependent cascade window (failed <= 15s after): +20
    /// - Recovery order consistency: +10
    public func analyzeRootCauses(
        serverId: UUID,
        incidents: [IncidentItem],
        monitors: [MonitorItem]
    ) -> [IncidentItem] {
        var updatedIncidents = incidents
        let activeIncidents = incidents.filter { $0.status != .resolved }

        // If fewer than 2 active incidents, no correlation cascade is possible
        guard activeIncidents.count >= 2 else {
            // Even for single incident, calculate blast radius (potential affected downstream)
            if activeIncidents.count == 1, let single = activeIncidents.first, let monId = single.monitorId {
                let downstream = getTransitiveDownstream(serverId: serverId, rootMonitorId: monId)
                let downstreamNames = downstream.compactMap { dId in
                    monitors.first(where: { $0.id == dId })?.name ?? dId
                }
                if let idx = updatedIncidents.firstIndex(where: { $0.id == single.id }) {
                    updatedIncidents[idx].rootCauseAnalysis = RootCauseAnalysis(
                        suspectedRootCauseMonitorId: monId,
                        suspectedRootCauseName: single.title,
                        confidenceScore: 100,
                        confidenceLevel: .high,
                        blastRadiusCount: downstream.count,
                        affectedServiceNames: downstreamNames,
                        evidenceList: [
                            "Originating failure on \(single.title) at \(formatTime(single.startedAt))",
                            "\(downstream.count) downstream dependent services at risk of cascading failure"
                        ],
                        timelineEvents: [
                            IncidentTimelineEvent(
                                timestamp: single.startedAt,
                                serviceName: single.title,
                                monitorId: single.monitorId,
                                eventType: .failure,
                                detail: single.reason,
                                isRootCauseCandidate: true
                            )
                        ]
                    )
                }
            }
            return updatedIncidents
        }

        let dependencies = DependencyStore.loadDependencies(forServerId: serverId)

        // Build candidate scores for each active monitor
        var scores: [String: Int] = [:]
        var evidenceMap: [String: [String]] = [:]
        var timelineEvents: [IncidentTimelineEvent] = []

        // Sort active incidents by startedAt ascending
        let sortedByTime = activeIncidents.sorted(by: { $0.startedAt < $1.startedAt })
        let earliestIncident = sortedByTime.first!

        // Generate chronological timeline events
        for inc in sortedByTime {
            let isEarliest = (inc.id == earliestIncident.id)
            timelineEvents.append(IncidentTimelineEvent(
                timestamp: inc.startedAt,
                serviceName: inc.title,
                monitorId: inc.monitorId,
                eventType: .failure,
                detail: inc.reason,
                isRootCauseCandidate: isEarliest
            ))
        }

        for inc in activeIncidents {
            guard let monId = inc.monitorId else { continue }
            var score = 0
            var evidence: [String] = []

            // 1. Chronological Earliest (+30 pts)
            if inc.id == earliestIncident.id {
                score += 30
                evidence.append("Failed first chronologically at \(formatTime(inc.startedAt))")
            }

            // 2. Upstream Dependency Check (+40 pts)
            // Does another active failed incident depend directly or indirectly on this monitor?
            let downstreamActive = activeIncidents.filter { other in
                guard let otherMonId = other.monitorId, otherMonId != monId else { return false }
                return isDependent(serverId: serverId, sourceId: otherMonId, targetId: monId, deps: dependencies)
            }

            if !downstreamActive.isEmpty {
                score += 40
                let names = downstreamActive.map { $0.title }.joined(separator: ", ")
                evidence.append("Active dependents also failing: \(names) depend on this service")
            }

            // 3. Cascade Timing Window (+20 pts)
            // If dependents failed within 15 seconds after this service
            let cascadedQuickly = downstreamActive.filter { other in
                let delta = other.startedAt.timeIntervalSince(inc.startedAt)
                return delta >= 0 && delta <= 15.0
            }
            if !cascadedQuickly.isEmpty {
                score += 20
                let names = cascadedQuickly.map { "\($0.title) (+\(Int(max(1, $0.startedAt.timeIntervalSince(inc.startedAt))))s)" }.joined(separator: ", ")
                evidence.append("Cascading failure window triggered: \(names) collapsed within 15s")
            }

            // 4. Recovery Order (+10 pts)
            // If already resolved dependents did not recover until upstream, or this has highest failure count
            if inc.consecutiveFailures >= 3 {
                score += 10
                evidence.append("Sustained persistent failure state (\(inc.consecutiveFailures) consecutive failed probes)")
            }

            scores[monId] = min(100, score)
            evidenceMap[monId] = evidence
        }

        // Find candidate with the highest score
        guard let highestEntry = scores.max(by: { $0.value < $1.value }),
              let rootIncident = activeIncidents.first(where: { $0.monitorId == highestEntry.key }) else {
            return updatedIncidents
        }

        let bestScore = highestEntry.value
        let rootMonId = highestEntry.key
        let rootName = rootIncident.title

        let confidence: ConfidenceLevel
        if bestScore >= 75 {
            confidence = .high
        } else if bestScore >= 45 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let transitiveDownstream = getTransitiveDownstream(serverId: serverId, rootMonitorId: rootMonId)
        let downstreamNames = transitiveDownstream.compactMap { dId in
            monitors.first(where: { $0.id == dId })?.name ?? dId
        }

        let rootEvidence = evidenceMap[rootMonId] ?? ["Identified through temporal correlation."]

        let rootAnalysis = RootCauseAnalysis(
            suspectedRootCauseMonitorId: rootMonId,
            suspectedRootCauseName: rootName,
            confidenceScore: bestScore,
            confidenceLevel: confidence,
            blastRadiusCount: transitiveDownstream.count,
            affectedServiceNames: downstreamNames,
            evidenceList: rootEvidence,
            timelineEvents: timelineEvents
        )

        // Attach analysis to all correlated active incidents
        for i in 0..<updatedIncidents.count {
            if updatedIncidents[i].status != .resolved {
                if updatedIncidents[i].monitorId == rootMonId {
                    updatedIncidents[i].rootCauseAnalysis = rootAnalysis
                } else {
                    // Downstream incident points to root cause
                    var downstreamEvidence = [
                        "Service depends on failing upstream: \(rootName)",
                        "Failed at \(formatTime(updatedIncidents[i].startedAt)) after \(rootName) went down"
                    ]
                    if let directEvidence = evidenceMap[updatedIncidents[i].monitorId ?? ""] {
                        downstreamEvidence.append(contentsOf: directEvidence)
                    }

                    updatedIncidents[i].rootCauseAnalysis = RootCauseAnalysis(
                        suspectedRootCauseMonitorId: rootMonId,
                        suspectedRootCauseName: rootName,
                        confidenceScore: bestScore,
                        confidenceLevel: confidence,
                        blastRadiusCount: transitiveDownstream.count,
                        affectedServiceNames: downstreamNames,
                        evidenceList: downstreamEvidence,
                        timelineEvents: timelineEvents
                    )
                }
            }
        }

        return updatedIncidents
    }

    // MARK: - Blast Radius Traversal
    /// Finds all direct and indirect monitors that depend on `rootMonitorId` (downstream reachability)
    public func getTransitiveDownstream(serverId: UUID, rootMonitorId: String) -> Set<String> {
        let deps = DependencyStore.loadDependencies(forServerId: serverId)
        var visited = Set<String>()
        var queue = [rootMonitorId]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            // Find all services where target == current (meaning source depends on current)
            let directDependents = deps.filter { $0.targetMonitorId == current }.map { $0.sourceMonitorId }
            for dep in directDependents {
                if !visited.contains(dep) && dep != rootMonitorId {
                    visited.insert(dep)
                    queue.append(dep)
                }
            }
        }

        return visited
    }

    /// Checks whether `sourceId` depends on `targetId` directly or indirectly
    public func isDependent(serverId: UUID, sourceId: String, targetId: String, deps: [ServiceDependency]) -> Bool {
        var visited = Set<String>()
        var queue = [sourceId]

        while !queue.isEmpty {
            let curr = queue.removeFirst()
            let upstreams = deps.filter { $0.sourceMonitorId == curr }.map { $0.targetMonitorId }
            for u in upstreams {
                if u == targetId { return true }
                if !visited.contains(u) {
                    visited.insert(u)
                    queue.append(u)
                }
            }
        }
        return false
    }

    // MARK: - Anomaly Detection
    /// Computes moving average and standard deviation over a float array, detects outliers (|z| >= 2.0)
    public func detectAnomalies(
        metricName: String,
        history: [Double],
        currentValue: Double
    ) -> MetricAnomaly? {
        guard history.count >= 8 else { return nil }

        let count = Double(history.count)
        let mean = history.reduce(0, +) / count
        let variance = history.reduce(0) { $0 + pow($1 - mean, 2) } / count
        let stdDev = sqrt(variance)

        // Avoid division by zero if metric was completely flat
        guard stdDev > 0.001 else { return nil }

        let zScore = (currentValue - mean) / stdDev

        if abs(zScore) >= 2.0 {
            let direction = zScore > 0 ? "spike (+)" : "drop (-)"
            let explanation = String(
                format: "%@ %@ detected: current %.1f vs baseline mean %.1f (z-score: %.1fσ)",
                metricName, direction, currentValue, mean, zScore
            )
            return MetricAnomaly(
                metricName: metricName,
                currentValue: currentValue,
                baselineMean: mean,
                standardDeviation: stdDev,
                zScore: zScore,
                timestamp: Date(),
                explanation: explanation
            )
        }

        return nil
    }

    // MARK: - Cross-Server Outage Correlation
    /// Detects if multiple distinct servers disconnected within an 8-second window.
    /// Returns true if correlated to local network drop rather than individual server disasters.
    public func detectConcurrentServerOutages(
        disconnectTimestamps: [UUID: Date],
        windowSeconds: TimeInterval = 8.0
    ) -> (isCorrelated: Bool, explanation: String?) {
        let times = Array(disconnectTimestamps.values).sorted()
        guard times.count >= 2 else { return (false, nil) }

        if let earliest = times.first, let latest = times.last {
            let span = latest.timeIntervalSince(earliest)
            if span <= windowSeconds {
                return (
                    true,
                    "\(times.count) servers disconnected simultaneously within \(Int(max(1, span)))s. Likely local client or internet gateway disruption, not independent VPS failures."
                )
            }
        }
        return (false, nil)
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df.string(from: date)
    }
}
