using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Pulse.Core.Models;

public enum HealthStatus
{
    Healthy,
    Warning,
    Critical,
    Down,
    Unknown
}

public class HealthResult
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("status")]
    public HealthStatus Status { get; set; } = HealthStatus.Unknown;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    [JsonPropertyName("latency_ms")]
    public long LatencyMs { get; set; }

    [JsonPropertyName("metrics")]
    public Dictionary<string, object>? Metrics { get; set; }

    [JsonPropertyName("last_checked")]
    public DateTime LastChecked { get; set; } = DateTime.UtcNow;
}
