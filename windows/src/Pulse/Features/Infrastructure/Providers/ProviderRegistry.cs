using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

namespace Pulse.Features.Infrastructure.Providers;

public class ProviderMetadata
{
    public string Type { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string Category { get; init; } = string.Empty;
    public ProviderCapability Capabilities { get; init; }
    public string Icon { get; init; } = "Cube";
}

public class ProviderRegistry
{
    private static readonly Lazy<ProviderRegistry> _instance = new(() => new ProviderRegistry());
    public static ProviderRegistry Instance => _instance.Value;

    private readonly ConcurrentDictionary<string, ProviderMetadata> _metadata = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, IProvider> _providers = new(StringComparer.OrdinalIgnoreCase);

    public ProviderRegistry()
    {
        RegisterBuiltIns();
    }

    private void RegisterBuiltIns()
    {
        // 1. Containers & Runtimes
        RegisterMetadata(new ProviderMetadata
        {
            Type = "docker",
            Name = "Docker Containers",
            Category = "Containers",
            Capabilities = ProviderCapability.Discovery | ProviderCapability.Health | ProviderCapability.Metrics | ProviderCapability.Actions | ProviderCapability.Logs,
            Icon = "Docker"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "systemd",
            Name = "Systemd Services",
            Category = "System",
            Capabilities = ProviderCapability.Discovery | ProviderCapability.Health | ProviderCapability.Actions | ProviderCapability.Logs,
            Icon = "Server"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "pm2",
            Name = "PM2 Process Manager",
            Category = "Runtimes",
            Capabilities = ProviderCapability.Discovery | ProviderCapability.Health | ProviderCapability.Metrics | ProviderCapability.Actions | ProviderCapability.Logs,
            Icon = "Play"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "process",
            Name = "Custom Process Monitor",
            Category = "System",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Cpu"
        });

        // 2. Databases
        RegisterMetadata(new ProviderMetadata
        {
            Type = "postgres",
            Name = "PostgreSQL",
            Category = "Databases",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Database"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "redis",
            Name = "Redis In-Memory Store",
            Category = "Databases",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Database"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "mysql",
            Name = "MySQL / MariaDB",
            Category = "Databases",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Database"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "mongodb",
            Name = "MongoDB Document DB",
            Category = "Databases",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Database"
        });

        // 3. Web & Edge Ingress
        RegisterMetadata(new ProviderMetadata
        {
            Type = "nginx",
            Name = "Nginx Web & Reverse Proxy",
            Category = "Web Servers",
            Capabilities = ProviderCapability.Discovery | ProviderCapability.Health | ProviderCapability.Metrics | ProviderCapability.Logs,
            Icon = "Globe"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "cloudflared",
            Name = "Cloudflare Tunnel",
            Category = "Networking",
            Capabilities = ProviderCapability.Discovery | ProviderCapability.Health | ProviderCapability.Metrics | ProviderCapability.Logs,
            Icon = "Cloud"
        });

        // 4. Probes & Custom Checks
        RegisterMetadata(new ProviderMetadata
        {
            Type = "http",
            Name = "Advanced HTTP/S Probe",
            Category = "Monitors",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Globe"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "tcp",
            Name = "TCP Port & TLS Expiry Probe",
            Category = "Monitors",
            Capabilities = ProviderCapability.Health | ProviderCapability.Metrics,
            Icon = "Network"
        });

        RegisterMetadata(new ProviderMetadata
        {
            Type = "custom",
            Name = "Custom Script Monitor",
            Category = "Monitors",
            Capabilities = ProviderCapability.Health,
            Icon = "Terminal"
        });
    }

    public void RegisterMetadata(ProviderMetadata metadata)
    {
        _metadata[metadata.Type] = metadata;
    }

    public void RegisterProvider(IProvider provider)
    {
        _providers[provider.Type] = provider;
    }

    public ProviderMetadata? GetMetadata(string type)
    {
        return _metadata.TryGetValue(type, out var m) ? m : null;
    }

    public IProvider? GetProvider(string type)
    {
        return _providers.TryGetValue(type, out var p) ? p : null;
    }

    public IReadOnlyList<ProviderMetadata> GetAllMetadata()
    {
        return _metadata.Values.ToList();
    }
}
