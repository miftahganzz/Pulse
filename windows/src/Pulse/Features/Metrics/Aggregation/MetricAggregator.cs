using System;
using System.Collections.Generic;
using System.Linq;

namespace Pulse.Features.Metrics.Aggregation;

public readonly record struct MetricPoint(DateTime Timestamp, double Value);

public class AggregatedMetricBucket
{
    public DateTime BucketStart { get; init; }
    public TimeSpan Duration { get; init; }
    public double Avg { get; init; }
    public double Min { get; init; }
    public double Max { get; init; }
    public double P95 { get; init; }
    public int Count { get; init; }
}

public class SlidingRingBuffer<T>
{
    private readonly T[] _buffer;
    private int _head;
    private int _count;
    private readonly object _lock = new();

    public int Capacity => _buffer.Length;
    public int Count { get { lock (_lock) return _count; } }

    public SlidingRingBuffer(int capacity = 360)
    {
        _buffer = new T[capacity];
        _head = 0;
        _count = 0;
    }

    public void Push(T item)
    {
        lock (_lock)
        {
            _buffer[_head] = item;
            _head = (_head + 1) % _buffer.Length;
            if (_count < _buffer.Length)
            {
                _count++;
            }
        }
    }

    public IReadOnlyList<T> ToList()
    {
        lock (_lock)
        {
            var result = new List<T>(_count);
            int start = (_head - _count + _buffer.Length) % _buffer.Length;
            for (int i = 0; i < _count; i++)
            {
                result.Add(_buffer[(start + i) % _buffer.Length]);
            }
            return result;
        }
    }
}

public class MetricAggregator
{
    private readonly SlidingRingBuffer<MetricPoint> _realtimeBuffer = new(360);
    private readonly List<AggregatedMetricBucket> _oneMinuteBuckets = new();
    private readonly List<AggregatedMetricBucket> _fiveMinuteBuckets = new();
    private readonly List<AggregatedMetricBucket> _oneHourBuckets = new();
    private readonly object _lock = new();

    public void AddRealtimePoint(DateTime timestamp, double value)
    {
        _realtimeBuffer.Push(new MetricPoint(timestamp, value));
    }

    public IReadOnlyList<MetricPoint> GetRealtimePoints() => _realtimeBuffer.ToList();

    public static AggregatedMetricBucket Aggregate(DateTime start, TimeSpan duration, IEnumerable<double> values)
    {
        var list = values.OrderBy(v => v).ToList();
        if (list.Count == 0)
        {
            return new AggregatedMetricBucket
            {
                BucketStart = start,
                Duration = duration,
                Avg = 0,
                Min = 0,
                Max = 0,
                P95 = 0,
                Count = 0
            };
        }

        double sum = list.Sum();
        double avg = Math.Round(sum / list.Count, 2);
        double min = Math.Round(list[0], 2);
        double max = Math.Round(list[^1], 2);

        int p95Index = (int)Math.Ceiling(0.95 * list.Count) - 1;
        if (p95Index < 0) p95Index = 0;
        if (p95Index >= list.Count) p95Index = list.Count - 1;
        double p95 = Math.Round(list[p95Index], 2);

        return new AggregatedMetricBucket
        {
            BucketStart = start,
            Duration = duration,
            Avg = avg,
            Min = min,
            Max = max,
            P95 = p95,
            Count = list.Count
        };
    }

    public void StoreBucket(TimeSpan duration, AggregatedMetricBucket bucket)
    {
        lock (_lock)
        {
            if (duration <= TimeSpan.FromMinutes(1))
            {
                _oneMinuteBuckets.Add(bucket);
                // Keep 7 days of 1-minute data (max ~10,080 entries)
                while (_oneMinuteBuckets.Count > 10080) _oneMinuteBuckets.RemoveAt(0);
            }
            else if (duration <= TimeSpan.FromMinutes(5))
            {
                _fiveMinuteBuckets.Add(bucket);
                // Keep 30 days of 5-minute data (max ~8,640 entries)
                while (_fiveMinuteBuckets.Count > 8640) _fiveMinuteBuckets.RemoveAt(0);
            }
            else
            {
                _oneHourBuckets.Add(bucket);
                // Keep 1 year of 1-hour data (max ~8,760 entries)
                while (_oneHourBuckets.Count > 8760) _oneHourBuckets.RemoveAt(0);
            }
        }
    }

    public IReadOnlyList<AggregatedMetricBucket> GetBuckets(string timeframe)
    {
        lock (_lock)
        {
            return timeframe switch
            {
                "1H" => _oneMinuteBuckets.TakeLast(60).ToList(),
                "6H" => _oneMinuteBuckets.TakeLast(360).ToList(),
                "24H" => _fiveMinuteBuckets.TakeLast(288).ToList(),
                "7D" => _fiveMinuteBuckets.TakeLast(2016).ToList(),
                "30D" => _oneHourBuckets.TakeLast(720).ToList(),
                _ => _oneMinuteBuckets.TakeLast(60).ToList()
            };
        }
    }
}
