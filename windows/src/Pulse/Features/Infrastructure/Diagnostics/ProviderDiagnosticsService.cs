using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Pulse.Core.Models;
using Pulse.Features.Infrastructure.Providers;

namespace Pulse.Features.Infrastructure.Diagnostics;

public class DiagnosticCheckResult
{
    public string Name { get; init; } = string.Empty;
    public bool Passed { get; init; }
    public string Message { get; init; } = string.Empty;
    public long LatencyMs { get; init; }
}

public class ProviderDiagnosticReport
{
    public string ProviderType { get; init; } = string.Empty;
    public string ProviderName { get; init; } = string.Empty;
    public bool IsOperational { get; init; }
    public List<DiagnosticCheckResult> Checks { get; init; } = new();
    public DateTime Timestamp { get; init; } = DateTime.UtcNow;
}

public class ProviderDiagnosticsService
{
    public async Task<ProviderDiagnosticReport> RunDiagnosticsAsync(string providerType, IProvider? provider, CancellationToken cancellationToken = default)
    {
        var report = new ProviderDiagnosticReport
        {
            ProviderType = providerType,
            ProviderName = provider?.Name ?? providerType,
            IsOperational = false
        };

        if (provider == null)
        {
            report.Checks.Add(new DiagnosticCheckResult
            {
                Name = "Provider Registration",
                Passed = false,
                Message = "Provider is not registered in runtime registry",
                LatencyMs = 0
            });
            return report;
        }

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var health = await provider.CheckHealthAsync("self", cancellationToken);
            sw.Stop();

            report.Checks.Add(new DiagnosticCheckResult
            {
                Name = "Daemon Reachability & Permission",
                Passed = health.Status == HealthStatus.Healthy || health.Status == HealthStatus.Warning,
                Message = health.Message,
                LatencyMs = sw.ElapsedMilliseconds
            });

            return new ProviderDiagnosticReport
            {
                ProviderType = providerType,
                ProviderName = provider.Name,
                IsOperational = health.Status != HealthStatus.Critical && health.Status != HealthStatus.Down,
                Checks = report.Checks,
                Timestamp = DateTime.UtcNow
            };
        }
        catch (Exception ex)
        {
            sw.Stop();
            report.Checks.Add(new DiagnosticCheckResult
            {
                Name = "Daemon Reachability & Permission",
                Passed = false,
                Message = $"Diagnostic check failed: {ex.Message}",
                LatencyMs = sw.ElapsedMilliseconds
            });
            return report;
        }
    }
}
