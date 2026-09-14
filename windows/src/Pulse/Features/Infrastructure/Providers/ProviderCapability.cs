using System;

namespace Pulse.Features.Infrastructure.Providers;

[Flags]
public enum ProviderCapability
{
    None = 0,
    Discovery = 1 << 0,
    Health = 1 << 1,
    Metrics = 1 << 2,
    Actions = 1 << 3,
    Logs = 1 << 4
}
