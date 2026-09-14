using System;
using System.Text.Json.Serialization;

namespace Pulse.Core.Models;

public struct CpuMetrics
{
    [JsonPropertyName("usage_percent")]
    public double UsagePercent { get; set; }

    [JsonPropertyName("cores")]
    public int Cores { get; set; }
}

public struct MemoryMetrics
{
    [JsonPropertyName("total_bytes")]
    public ulong TotalBytes { get; set; }

    [JsonPropertyName("used_bytes")]
    public ulong UsedBytes { get; set; }

    [JsonPropertyName("free_bytes")]
    public ulong FreeBytes { get; set; }

    [JsonPropertyName("usage_percent")]
    public double UsagePercent { get; set; }

    public double UsedGigabytes => Math.Round(UsedBytes / (1024.0 * 1024.0 * 1024.0), 2);
    public double TotalGigabytes => Math.Round(TotalBytes / (1024.0 * 1024.0 * 1024.0), 2);
}

public struct DiskMetrics
{
    [JsonPropertyName("total_bytes")]
    public ulong TotalBytes { get; set; }

    [JsonPropertyName("used_bytes")]
    public ulong UsedBytes { get; set; }

    [JsonPropertyName("usage_percent")]
    public double UsagePercent { get; set; }

    public double UsedGigabytes => Math.Round(UsedBytes / (1024.0 * 1024.0 * 1024.0), 1);
    public double TotalGigabytes => Math.Round(TotalBytes / (1024.0 * 1024.0 * 1024.0), 1);
}

public struct NetworkMetrics
{
    [JsonPropertyName("rx_bytes_per_sec")]
    public double RxBytesPerSec { get; set; }

    [JsonPropertyName("tx_bytes_per_sec")]
    public double TxBytesPerSec { get; set; }
}

public class SystemMetrics
{
    [JsonPropertyName("timestamp")]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    [JsonPropertyName("cpu")]
    public CpuMetrics Cpu { get; set; }

    [JsonPropertyName("memory")]
    public MemoryMetrics Memory { get; set; }

    [JsonPropertyName("disk")]
    public DiskMetrics Disk { get; set; }

    [JsonPropertyName("network")]
    public NetworkMetrics Network { get; set; }

    [JsonPropertyName("load_avg")]
    public double[] LoadAvg { get; set; } = new double[3];

    [JsonPropertyName("uptime_seconds")]
    public ulong UptimeSeconds { get; set; }
}
