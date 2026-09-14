using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Pulse.Core.Models;

namespace Pulse.Features.Infrastructure.Providers;

public interface IProvider
{
    string Type { get; }
    string Name { get; }
    ProviderCapability Capabilities { get; }

    Task<IReadOnlyList<DiscoveredService>> DiscoverAsync(CancellationToken cancellationToken = default);
    Task<HealthResult> CheckHealthAsync(string target, CancellationToken cancellationToken = default);
}
