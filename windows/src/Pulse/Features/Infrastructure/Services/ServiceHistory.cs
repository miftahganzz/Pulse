using System;
using System.Collections.Generic;

namespace Pulse.Features.Infrastructure.Services;

public class ServiceHistory
{
    public string ServiceId { get; init; } = string.Empty;
    public string ServiceName { get; init; } = string.Empty;
    public long TotalChecks { get; private set; }
    public long HealthyChecks { get; private set; }
    public long FailedChecks { get; private set; }
    public int IncidentCount { get; private set; }
    public DateTime? LastIncidentAt { get; private set; }
    public DateTime FirstSeenAt { get; private set; } = DateTime.UtcNow;
    public DateTime LastCheckedAt { get; private set; } = DateTime.UtcNow;

    private readonly Queue<long> _recentLatenciesMs = new();
    private const int MaxLatencyPoints = 60;

    public void RecordCheck(bool isHealthy, long latencyMs = 0)
    {
        TotalChecks++;
        LastCheckedAt = DateTime.UtcNow;

        if (isHealthy)
        {
            HealthyChecks++;
        }
        else
        {
            FailedChecks++;
            IncidentCount++;
            LastIncidentAt = DateTime.UtcNow;
        }

        if (latencyMs > 0)
        {
            _recentLatenciesMs.Enqueue(latencyMs);
            while (_recentLatenciesMs.Count > MaxLatencyPoints)
            {
                _recentLatenciesMs.Dequeue();
            }
        }
    }

    public double AvailabilityPercent => AvailabilityCalculator.CalculateAvailability(HealthyChecks, TotalChecks);

    public double AverageLatencyMs
    {
        get
        {
            if (_recentLatenciesMs.Count == 0) return 0;
            long sum = 0;
            foreach (var l in _recentLatenciesMs) sum += l;
            return Math.Round((double)sum / _recentLatenciesMs.Count, 1);
        }
    }
}
