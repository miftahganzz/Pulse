using System;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Pulse.Features.Updates;

public enum UpdateState
{
    Idle,
    Checking,
    Downloading,
    Verifying,
    Staging,
    Restarting,
    VerifyingHealth,
    RollingBack,
    Completed,
    Failed
}

public class UpdateProgressReport
{
    public UpdateState State { get; init; }
    public string Message { get; init; } = string.Empty;
    public int Percent { get; init; }
}

public class UpdateVerificationService
{
    public static bool VerifyChecksum(byte[] binaryData, string expectedSha256Hex)
    {
        if (binaryData == null || binaryData.Length == 0 || string.IsNullOrWhiteSpace(expectedSha256Hex))
        {
            return false;
        }

        using var sha256 = SHA256.Create();
        byte[] hash = sha256.ComputeHash(binaryData);
        string calculatedHex = Convert.ToHexString(hash);

        return string.Equals(calculatedHex, expectedSha256Hex.Trim(), StringComparison.OrdinalIgnoreCase);
    }
}

public class AgentUpdateService
{
    public UpdateState CurrentState { get; private set; } = UpdateState.Idle;

    public async Task<bool> ExecuteSafeUpdateAsync(
        string targetVersion,
        string expectedChecksum,
        Func<CancellationToken, Task<byte[]>> downloadBinaryFunc,
        Func<byte[], CancellationToken, Task<bool>> stageAndRestartFunc,
        Func<CancellationToken, Task<bool>> healthCheckFunc,
        Func<CancellationToken, Task<bool>> rollbackFunc,
        IProgress<UpdateProgressReport>? progress = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // 1. Download
            CurrentState = UpdateState.Downloading;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = $"Downloading pulse-agent {targetVersion}...", Percent = 20 });
            byte[] binaryData = await downloadBinaryFunc(cancellationToken);

            // 2. Verification
            CurrentState = UpdateState.Verifying;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = "Verifying binary integrity (SHA-256)...", Percent = 40 });
            if (!UpdateVerificationService.VerifyChecksum(binaryData, expectedChecksum))
            {
                throw new InvalidOperationException("Binary checksum mismatch! Update aborted to protect server integrity.");
            }

            // 3. Staging & Atomic Replace
            CurrentState = UpdateState.Staging;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = "Staging binary and preparing atomic restart...", Percent = 60 });

            CurrentState = UpdateState.Restarting;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = "Restarting pulse-agent service...", Percent = 80 });
            bool staged = await stageAndRestartFunc(binaryData, cancellationToken);
            if (!staged)
            {
                throw new InvalidOperationException("Failed to stage binary or trigger service restart.");
            }

            // 4. Verify Health post-update
            CurrentState = UpdateState.VerifyingHealth;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = "Verifying post-update health check...", Percent = 90 });
            await Task.Delay(3000, cancellationToken); // Give systemd time to spin up
            bool isHealthy = await healthCheckFunc(cancellationToken);

            if (!isHealthy)
            {
                // Trigger rollback
                CurrentState = UpdateState.RollingBack;
                progress?.Report(new UpdateProgressReport { State = CurrentState, Message = "Health check failed! Rolling back to previous agent binary...", Percent = 95 });
                await rollbackFunc(cancellationToken);
                CurrentState = UpdateState.Failed;
                return false;
            }

            CurrentState = UpdateState.Completed;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = $"pulse-agent updated to {targetVersion} successfully!", Percent = 100 });
            return true;
        }
        catch (Exception ex)
        {
            CurrentState = UpdateState.Failed;
            progress?.Report(new UpdateProgressReport { State = CurrentState, Message = $"Update failed: {ex.Message}", Percent = 0 });
            return false;
        }
    }
}
