using System;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Pulse.Core.Models;

namespace Pulse.Core.Network;

public class HandshakeMessage
{
    public int Protocol { get; set; } = 2;
    public string ClientVersion { get; set; } = "1.0.6";
    public string[] ClientCapabilities { get; set; } = new[]
    {
        "metrics", "docker", "pm2", "systemd", "postgres", "redis", "mysql", "mongodb", "nginx", "cloudflared", "logs", "actions"
    };
}

public class PulseAgentClient : IAsyncDisposable
{
    private readonly ServerModel _server;
    private ClientWebSocket? _webSocket;
    private CancellationTokenSource? _cts;
    private Task? _receiveLoopTask;

    public event Action<SystemMetrics>? MetricsReceived;
    public event Action<string>? LogLineReceived;
    public event Action<bool>? ConnectionStateChanged;

    public bool IsConnected => _webSocket?.State == WebSocketState.Open;

    public PulseAgentClient(ServerModel server)
    {
        _server = server;
    }

    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        _cts = new CancellationTokenSource();
        _webSocket = new ClientWebSocket();

        // Configure headers
        if (!string.IsNullOrEmpty(_server.AuthToken))
        {
            _webSocket.Options.SetRequestHeader("Authorization", $"Bearer {_server.AuthToken}");
        }

        string scheme = _server.UseTls ? "wss" : "ws";
        var uri = new Uri($"{scheme}://{_server.Host}:{_server.Port}/ws/metrics");

        await _webSocket.ConnectAsync(uri, cancellationToken);
        ConnectionStateChanged?.Invoke(true);

        // Send Protocol v2 Handshake
        await SendHandshakeAsync(_cts.Token);

        // Start receive loop
        _receiveLoopTask = Task.Run(() => ReceiveLoopAsync(_cts.Token), _cts.Token);
    }

    private async Task SendHandshakeAsync(CancellationToken cancellationToken)
    {
        if (_webSocket?.State != WebSocketState.Open) return;

        var handshake = new HandshakeMessage();
        string json = JsonSerializer.Serialize(handshake);
        byte[] bytes = Encoding.UTF8.GetBytes(json);

        await _webSocket.SendAsync(
            new ArraySegment<byte>(bytes),
            WebSocketMessageType.Text,
            true,
            cancellationToken);
    }

    private async Task ReceiveLoopAsync(CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        var ms = new MemoryStream();

        try
        {
            while (!cancellationToken.IsCancellationRequested && _webSocket?.State == WebSocketState.Open)
            {
                WebSocketReceiveResult result;
                ms.SetLength(0);

                do
                {
                    result = await _webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", cancellationToken);
                        ConnectionStateChanged?.Invoke(false);
                        return;
                    }

                    ms.Write(buffer, 0, result.Count);
                }
                while (!result.EndOfMessage);

                string message = Encoding.UTF8.GetString(ms.ToArray());
                ProcessIncomingMessage(message);
            }
        }
        catch (OperationCanceledException)
        {
            // Expected on disconnect
        }
        catch (Exception)
        {
            ConnectionStateChanged?.Invoke(false);
        }
    }

    private void ProcessIncomingMessage(string message)
    {
        try
        {
            using var doc = JsonDocument.Parse(message);
            var root = doc.RootElement;

            if (root.TryGetProperty("type", out var typeProp))
            {
                string msgType = typeProp.GetString() ?? "";
                if (msgType == "metrics" && root.TryGetProperty("payload", out var payload))
                {
                    var metrics = JsonSerializer.Deserialize<SystemMetrics>(payload.GetRawText());
                    if (metrics != null)
                    {
                        MetricsReceived?.Invoke(metrics);
                    }
                }
                else if (msgType == "log" && root.TryGetProperty("line", out var line))
                {
                    LogLineReceived?.Invoke(line.GetString() ?? "");
                }
            }
            else
            {
                // Raw metrics fallback
                var metrics = JsonSerializer.Deserialize<SystemMetrics>(message);
                if (metrics != null)
                {
                    MetricsReceived?.Invoke(metrics);
                }
            }
        }
        catch
        {
            // Ignore malformed packet
        }
    }

    public async Task DisconnectAsync()
    {
        _cts?.Cancel();
        if (_webSocket != null && _webSocket.State == WebSocketState.Open)
        {
            await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Client disconnected", CancellationToken.None);
        }
        _webSocket?.Dispose();
        _webSocket = null;
        ConnectionStateChanged?.Invoke(false);
    }

    public async ValueTask DisposeAsync()
    {
        await DisconnectAsync();
        _cts?.Dispose();
    }
}
