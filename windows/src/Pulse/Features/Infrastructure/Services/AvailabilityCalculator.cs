using System;

namespace Pulse.Features.Infrastructure.Services;

public static class AvailabilityCalculator
{
    public const string Disclaimer = "Availability based on Pulse checks";

    public static double CalculateAvailability(long healthyChecks, long totalChecks)
    {
        if (totalChecks <= 0) return 100.0;
        if (healthyChecks <= 0) return 0.0;
        if (healthyChecks >= totalChecks) return 100.0;

        double percent = ((double)healthyChecks / totalChecks) * 100.0;
        return Math.Round(percent, 2);
    }

    public static string FormatAvailability(double percentage)
    {
        return $"{percentage:F2}%";
    }
}
