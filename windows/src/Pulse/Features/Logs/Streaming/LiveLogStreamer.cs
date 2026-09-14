using System;
using System.Collections.Generic;
using System.Linq;
using Pulse.Features.Logs.Sanitization;
using Pulse.Features.Metrics.Aggregation;

namespace Pulse.Features.Logs.Streaming;

public enum LogLevel
{
    All,
    Info,
    Warning,
    Error
}

public class LogEntry
{
    public DateTime Timestamp { get; init; } = DateTime.UtcNow;
    public string Message { get; init; } = string.Empty;
    public LogLevel Level { get; init; } = LogLevel.Info;
    public string Source { get; init; } = "system";

    public static LogLevel DetectLevel(string line)
    {
        string lower = line.ToLowerInvariant();
        if (lower.Contains("err") || lower.Contains("crit") || lower.Contains("fatal") || lower.Contains("panic") || lower.Contains("fail"))
        {
            return LogLevel.Error;
        }
        if (lower.Contains("warn"))
        {
            return LogLevel.Warning;
        }
        return LogLevel.Info;
    }
}

public class LiveLogStreamer
{
    private readonly SlidingRingBuffer<LogEntry> _buffer;
    public int MaxCapacity => _buffer.Capacity;

    public LiveLogStreamer(int maxCapacity = 5000)
    {
        _buffer = new SlidingRingBuffer<LogEntry>(maxCapacity);
    }

    public void IngestLine(string rawLine, string source = "system")
    {
        string sanitized = LogSanitizer.Sanitize(rawLine);
        LogLevel level = LogEntry.DetectLevel(sanitized);

        _buffer.Push(new LogEntry
        {
            Timestamp = DateTime.UtcNow,
            Message = sanitized,
            Level = level,
            Source = source
        });
    }

    public IReadOnlyList<LogEntry> Filter(LogLevel levelFilter = LogLevel.All, string? searchQuery = null, int limit = 500)
    {
        var entries = _buffer.ToList();
        var query = entries.AsEnumerable();

        if (levelFilter != LogLevel.All)
        {
            query = query.Where(e => e.Level == levelFilter);
        }

        if (!string.IsNullOrWhiteSpace(searchQuery))
        {
            query = query.Where(e => e.Message.Contains(searchQuery, StringComparison.OrdinalIgnoreCase));
        }

        return query.TakeLast(limit).ToList();
    }
}
