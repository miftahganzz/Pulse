using System;
using System.Text.RegularExpressions;

namespace Pulse.Features.Logs.Sanitization;

public static class LogSanitizer
{
    private static readonly Regex BearerTokenRegex = new(
        @"(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex PasswordRegex = new(
        @"(password|passwd|pwd|secret|api_key|apikey|token|auth_token)(\s*[:=]\s*)(['""]?)[^'"";\s]+(['""]?)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex PrivateKeyRegex = new(
        @"-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+ PRIVATE KEY-----",
        RegexOptions.Compiled);

    public static string Sanitize(string logLine)
    {
        if (string.IsNullOrEmpty(logLine))
        {
            return logLine;
        }

        // 1. Redact Bearer Authorization
        string sanitized = BearerTokenRegex.Replace(logLine, "$1[REDACTED]");

        // 2. Redact key-value secrets
        sanitized = PasswordRegex.Replace(sanitized, "$1$2$3[REDACTED]$4");

        // 3. Redact multi-line private keys
        sanitized = PrivateKeyRegex.Replace(sanitized, "[REDACTED PRIVATE KEY]");

        return sanitized;
    }
}
