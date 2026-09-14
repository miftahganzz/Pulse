using System;
using System.Collections.Generic;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using Pulse.Features.Metrics.Aggregation;

namespace Pulse.Features.Metrics.Charts;

public partial class MetricChartViewModel : ObservableObject
{
    [ObservableProperty]
    private string _title = "CPU Usage";

    [ObservableProperty]
    private string _timeRange = "1H";

    [ObservableProperty]
    private double _currentValue;

    [ObservableProperty]
    private double _minValue;

    [ObservableProperty]
    private double _maxValue;

    [ObservableProperty]
    private double _avgValue;

    public IReadOnlyList<MetricPoint> Downsample(IReadOnlyList<MetricPoint> source, int targetPoints = 60)
    {
        if (source.Count <= targetPoints)
        {
            return source;
        }

        var result = new List<MetricPoint>(targetPoints);
        double step = (double)(source.Count - 1) / (targetPoints - 1);

        for (int i = 0; i < targetPoints; i++)
        {
            int index = (int)Math.Round(i * step);
            if (index >= source.Count) index = source.Count - 1;
            result.Add(source[index]);
        }

        return result;
    }

    public void UpdateSeries(IReadOnlyList<MetricPoint> points)
    {
        if (points.Count == 0) return;

        CurrentValue = Math.Round(points[^1].Value, 1);
        MinValue = Math.Round(points.Min(p => p.Value), 1);
        MaxValue = Math.Round(points.Max(p => p.Value), 1);
        AvgValue = Math.Round(points.Average(p => p.Value), 1);
    }
}
