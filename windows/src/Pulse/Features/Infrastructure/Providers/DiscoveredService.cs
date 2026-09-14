using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Pulse.Features.Infrastructure.Providers;

public class DiscoveredService
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("provider_type")]
    public string ProviderType { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("status")]
    public string Status { get; set; } = "unknown";

    [JsonPropertyName("metadata")]
    public Dictionary<string, string> Metadata { get; set; } = new();
}
