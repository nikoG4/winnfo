using System.Text.Json;
using Inspector.Core.Models;

namespace Inspector.Infrastructure.ExternalTools;

public sealed class SmartctlService
{
    public async Task<SmartInfo> ReadAsync(int physicalDriveIndex, string? expectedModel, string? expectedSerial, CancellationToken cancellationToken)
    {
        var smartctl = FindSmartctl();
        if (smartctl is null)
            return new SmartInfo { Available = false, Source = "smartctl", Error = "smartctl.exe not found in PATH, app tools folder, or Program Files." };

        var attempts = new List<SmartctlAttempt> { new($"/dev/physicaldrive{physicalDriveIndex}", null) };
        attempts.AddRange(await ScanDevicesAsync(smartctl, cancellationToken).ConfigureAwait(false));

        var errors = new List<string>();
        foreach (var attempt in attempts.DistinctBy(a => $"{a.Device}|{a.DeviceType}"))
        {
            var args = attempt.DeviceType is null
                ? $"-a -j {attempt.Device}"
                : $"-a -j -d {attempt.DeviceType} {attempt.Device}";
            var result = await ProcessRunner.RunAsync(smartctl, args, TimeSpan.FromSeconds(15), cancellationToken).ConfigureAwait(false);
            var info = ParseSmartctl(result.StandardOutput, expectedModel, expectedSerial, out var matchesExpected);
            if (info.Available && (matchesExpected || attempts.Count == 1 || (string.IsNullOrWhiteSpace(expectedModel) && string.IsNullOrWhiteSpace(expectedSerial))))
            {
                info.Source = attempt.DeviceType is null ? "smartctl" : $"smartctl ({attempt.Device} -d {attempt.DeviceType})";
                return info;
            }

            var stderr = string.IsNullOrWhiteSpace(result.StandardError) ? ExtractSmartctlError(result.StandardOutput) : result.StandardError.Trim();
            if (!string.IsNullOrWhiteSpace(stderr))
                errors.Add($"{args}: {stderr}");
        }

        return new SmartInfo { Available = false, Source = "smartctl", Error = string.Join("; ", errors.Distinct()) };
    }

    private static SmartInfo ParseSmartctl(string json, string? expectedModel, string? expectedSerial, out bool matchesExpected)
    {
        matchesExpected = false;
        if (string.IsNullOrWhiteSpace(json))
            return new SmartInfo { Available = false, Source = "smartctl", Error = "Empty smartctl output" };

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (!SmartctlSucceeded(root))
                return new SmartInfo { Available = false, Source = "smartctl", Error = ExtractSmartctlError(json) };

            var model = root.TryGetProperty("model_name", out var modelElement) ? modelElement.GetString() : null;
            var serial = root.TryGetProperty("serial_number", out var serialElement) ? serialElement.GetString() : null;
            matchesExpected = Matches(expectedModel, model) || SameSerial(expectedSerial, serial);

            var totalHostWritesGb = FindBytesAsGb(root, "nvme_smart_health_information_log", "data_units_written");
            if (totalHostWritesGb is null)
            {
                var lbasWritten = FindAttribute(root, "Total_LBAs_Written");
                if (lbasWritten.HasValue)
                    totalHostWritesGb = lbasWritten.Value * 512d / 1_000_000_000d;
            }

            return new SmartInfo
            {
                Available = true,
                Source = "smartctl",
                RawJson = json,
                PowerOnHours = FindInt(root, "power_on_time", "hours") ?? FindAttribute(root, "Power_On_Hours"),
                PowerCycles = FindInt(root, "power_cycle_count"),
                HealthPercent = FindPercentageUsed(root) is int used ? Math.Clamp(100 - used, 0, 100) : FindAttribute(root, "Percent_Lifetime_Remain"),
                TemperatureCelsius = FindDouble(root, "temperature", "current") ?? FindDouble(root, "temperature", "current_temperature"),
                TotalHostWritesGb = totalHostWritesGb,
                UnsafeShutdowns = FindInt(root, "nvme_smart_health_information_log", "unsafe_shutdowns")
            };
        }
        catch (Exception ex)
        {
            return new SmartInfo { Available = false, Source = "smartctl", Error = $"Invalid smartctl JSON: {ex.Message}" };
        }
    }

    private static async Task<List<SmartctlAttempt>> ScanDevicesAsync(string smartctl, CancellationToken cancellationToken)
    {
        var result = await ProcessRunner.RunAsync(smartctl, "--scan-open", TimeSpan.FromSeconds(10), cancellationToken).ConfigureAwait(false);
        var attempts = new List<SmartctlAttempt>();
        foreach (var line in result.StandardOutput.Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0 || !parts[0].StartsWith("/dev/", StringComparison.OrdinalIgnoreCase)) continue;
            var type = parts.Length >= 3 && parts[1] == "-d" ? parts[2] : null;
            attempts.Add(new(parts[0], type));
        }
        return attempts;
    }

    private static string? FindSmartctl()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "tools", "smartctl.exe"),
            Path.Combine(AppContext.BaseDirectory, "tools", "smartmontools", "bin", "smartctl.exe"),
            Path.Combine(Environment.CurrentDirectory, "tools", "smartctl.exe"),
            Path.Combine(Environment.CurrentDirectory, "tools", "smartmontools", "bin", "smartctl.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "smartmontools", "bin", "smartctl.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "smartmontools", "bin", "smartctl.exe")
        };
        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate)) return candidate;
        }

        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(dir.Trim(), "smartctl.exe");
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    private static bool SmartctlSucceeded(JsonElement root)
        => root.TryGetProperty("smartctl", out var smartctl) &&
           smartctl.TryGetProperty("exit_status", out var exitStatus) &&
           exitStatus.TryGetInt32(out var status) &&
           status == 0;

    private static string ExtractSmartctlError(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("smartctl", out var smartctl) &&
                smartctl.TryGetProperty("messages", out var messages) &&
                messages.ValueKind == JsonValueKind.Array)
            {
                return string.Join("; ", messages.EnumerateArray()
                    .Select(m => m.TryGetProperty("string", out var text) ? text.GetString() : null)
                    .Where(m => !string.IsNullOrWhiteSpace(m)));
            }
        }
        catch { }
        return "";
    }

    private static bool Matches(string? expected, string? actual)
        => !string.IsNullOrWhiteSpace(expected) &&
           !string.IsNullOrWhiteSpace(actual) &&
           (expected.Contains(actual, StringComparison.OrdinalIgnoreCase) ||
            actual.Contains(expected, StringComparison.OrdinalIgnoreCase));

    private static bool SameSerial(string? left, string? right)
    {
        static string Clean(string? value) => new((value ?? "").Where(char.IsLetterOrDigit).ToArray());
        var a = Clean(left);
        var b = Clean(right);
        return a.Length > 0 && b.Length > 0 && (a.Contains(b, StringComparison.OrdinalIgnoreCase) || b.Contains(a, StringComparison.OrdinalIgnoreCase));
    }

    private static int? FindAttribute(JsonElement root, string name)
    {
        if (root.TryGetProperty("ata_smart_attributes", out var attrs) &&
            attrs.TryGetProperty("table", out var table) &&
            table.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in table.EnumerateArray())
            {
                if (item.TryGetProperty("name", out var n) && string.Equals(n.GetString(), name, StringComparison.OrdinalIgnoreCase))
                {
                    if (item.TryGetProperty("raw", out var raw) && raw.TryGetProperty("value", out var value) && value.TryGetInt32(out var parsed)) return parsed;
                    if (item.TryGetProperty("value", out var normalized) && normalized.TryGetInt32(out parsed)) return parsed;
                }
            }
        }
        return null;
    }

    private static int? FindPercentageUsed(JsonElement root) => FindInt(root, "nvme_smart_health_information_log", "percentage_used");

    private static int? FindInt(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var part in path)
        {
            if (!current.TryGetProperty(part, out current)) return null;
        }
        return current.ValueKind == JsonValueKind.Number && current.TryGetInt32(out var value) ? value : null;
    }

    private static double? FindDouble(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var part in path)
        {
            if (!current.TryGetProperty(part, out current)) return null;
        }
        return current.ValueKind == JsonValueKind.Number && current.TryGetDouble(out var value) ? value : null;
    }

    private static double? FindBytesAsGb(JsonElement root, params string[] path)
    {
        var value = FindDouble(root, path);
        return value is null ? null : value.Value * 512000d / 1_000_000_000d;
    }
}

internal sealed record SmartctlAttempt(string Device, string? DeviceType);
