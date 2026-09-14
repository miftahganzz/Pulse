using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Pulse.Core.Models;

public enum ServerEnvironment
{
    Production,
    Staging,
    Development,
    Untagged
}

public class ServerModel
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("host")]
    public string Host { get; set; } = string.Empty;

    [JsonPropertyName("port")]
    public int Port { get; set; } = 9443;

    [JsonPropertyName("auth_token")]
    public string AuthToken { get; set; } = string.Empty;

    [JsonPropertyName("environment")]
    public ServerEnvironment Environment { get; set; } = ServerEnvironment.Untagged;

    [JsonPropertyName("tags")]
    public List<string> Tags { get; set; } = new();

    [JsonPropertyName("use_tls")]
    public bool UseTls { get; set; } = true;

    [JsonPropertyName("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public string DisplayAddress => $"{Host}:{Port}";
}
