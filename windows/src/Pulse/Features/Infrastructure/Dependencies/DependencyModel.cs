using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;

namespace Pulse.Features.Infrastructure.Dependencies;

public enum DependencyType
{
    [JsonPropertyName("depends_on")]
    DependsOn,

    [JsonPropertyName("connects_to")]
    ConnectsTo,

    [JsonPropertyName("serves")]
    Serves,

    [JsonPropertyName("runs_on")]
    RunsOn,

    [JsonPropertyName("monitors")]
    Monitors
}

public class Dependency
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("source_id")]
    public string SourceId { get; set; } = string.Empty;

    [JsonPropertyName("target_id")]
    public string TargetId { get; set; } = string.Empty;

    [JsonPropertyName("type")]
    public DependencyType Type { get; set; } = DependencyType.DependsOn;

    [JsonPropertyName("required")]
    public bool Required { get; set; } = true;

    [JsonPropertyName("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class DependencyGraph
{
    private readonly List<Dependency> _dependencies = new();
    private readonly object _lock = new();

    public void AddDependency(Dependency dep)
    {
        lock (_lock)
        {
            if (!_dependencies.Any(d => d.SourceId == dep.SourceId && d.TargetId == dep.TargetId && d.Type == dep.Type))
            {
                _dependencies.Add(dep);
            }
        }
    }

    public void RemoveDependency(string id)
    {
        lock (_lock)
        {
            _dependencies.RemoveAll(d => d.Id == id);
        }
    }

    public IReadOnlyList<Dependency> GetDependenciesFor(string serviceId)
    {
        lock (_lock)
        {
            return _dependencies.Where(d => d.SourceId == serviceId).ToList();
        }
    }

    public IReadOnlyList<Dependency> GetDependentsOf(string serviceId)
    {
        lock (_lock)
        {
            return _dependencies.Where(d => d.TargetId == serviceId).ToList();
        }
    }

    public IReadOnlyList<Dependency> GetAll()
    {
        lock (_lock)
        {
            return _dependencies.ToList();
        }
    }
}
