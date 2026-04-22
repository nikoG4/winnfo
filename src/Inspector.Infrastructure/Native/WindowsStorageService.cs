using System.Text.Json;
using Inspector.Core.Models;
using Inspector.Infrastructure.ExternalTools;

namespace Inspector.Infrastructure.Native;

public sealed class WindowsStorageService
{
    public async Task<List<PhysicalDiskSnapshot>> ReadPhysicalDisksAsync(CancellationToken cancellationToken)
    {
        const string command = "Get-PhysicalDisk | Select-Object DeviceId,FriendlyName,SerialNumber,MediaType,BusType,HealthStatus,OperationalStatus,Size | ConvertTo-Json -Depth 4";
        var result = await ProcessRunner.RunAsync("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"", TimeSpan.FromSeconds(12), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0 || string.IsNullOrWhiteSpace(result.StandardOutput))
            return [];

        try
        {
            return JsonSerializer.Deserialize<List<PhysicalDiskSnapshot>>(NormalizeJsonArray(result.StandardOutput), JsonOptions()) ?? [];
        }
        catch
        {
            return [];
        }
    }

    public async Task<StorageReliabilityResult> ReadReliabilityAsync(CancellationToken cancellationToken)
    {
        const string script =
            "$items = @(); " +
            "Get-PhysicalDisk | ForEach-Object { " +
            "$pd = $_; " +
            "try { $rc = $pd | Get-StorageReliabilityCounter -ErrorAction Stop; " +
            "$items += [pscustomobject]@{ DeviceId=$pd.DeviceId; FriendlyName=$pd.FriendlyName; SerialNumber=$pd.SerialNumber; PowerOnHours=$rc.PowerOnHours; PowerCycleCount=$rc.PowerCycleCount; Temperature=$rc.Temperature; Wear=$rc.Wear; ReadErrorsTotal=$rc.ReadErrorsTotal; WriteErrorsTotal=$rc.WriteErrorsTotal; Error=$null } " +
            "} catch { " +
            "$items += [pscustomobject]@{ DeviceId=$pd.DeviceId; FriendlyName=$pd.FriendlyName; SerialNumber=$pd.SerialNumber; PowerOnHours=$null; PowerCycleCount=$null; Temperature=$null; Wear=$null; ReadErrorsTotal=$null; WriteErrorsTotal=$null; Error=$_.Exception.Message } " +
            "} }; $items | ConvertTo-Json -Depth 4";

        var escaped = script.Replace("\"", "\\\"");
        var result = await ProcessRunner.RunAsync("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{escaped}\"", TimeSpan.FromSeconds(18), cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(result.StandardOutput))
            return new StorageReliabilityResult([], result.StandardError.Trim());

        try
        {
            var rows = JsonSerializer.Deserialize<List<StorageReliabilitySnapshot>>(NormalizeJsonArray(result.StandardOutput), JsonOptions()) ?? [];
            return new StorageReliabilityResult(rows, result.ExitCode == 0 ? null : result.StandardError.Trim());
        }
        catch (Exception ex)
        {
            return new StorageReliabilityResult([], $"Could not parse Get-StorageReliabilityCounter output: {ex.Message}");
        }
    }

    public async Task<Dictionary<int, List<string>>> ReadDriveLettersAsync(CancellationToken cancellationToken)
    {
        const string command = "Get-Partition | Where-Object { $_.DriveLetter } | Select-Object DiskNumber,DriveLetter | ConvertTo-Json -Depth 3";
        var result = await ProcessRunner.RunAsync("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"", TimeSpan.FromSeconds(10), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0 || string.IsNullOrWhiteSpace(result.StandardOutput))
            return [];

        try
        {
            var rows = JsonSerializer.Deserialize<List<PartitionSnapshot>>(NormalizeJsonArray(result.StandardOutput), JsonOptions()) ?? [];
            return rows
                .Where(r => r.DiskNumber.HasValue && !string.IsNullOrWhiteSpace(r.DriveLetter))
                .GroupBy(r => r.DiskNumber!.Value)
                .ToDictionary(g => g.Key, g => g.Select(r => $"{r.DriveLetter}:").Distinct(StringComparer.OrdinalIgnoreCase).ToList());
        }
        catch
        {
            return [];
        }
    }

    public static void ApplyPhysicalDisk(StorageDeviceInfo target, PhysicalDiskSnapshot snapshot)
    {
        if (!string.IsNullOrWhiteSpace(snapshot.BusType))
            target.BusType = snapshot.BusType;
        if (!string.IsNullOrWhiteSpace(snapshot.MediaType))
            target.MediaType = snapshot.MediaType;
        if (!string.IsNullOrWhiteSpace(snapshot.HealthStatus) && target.Smart.HealthPercent is null)
            target.Smart.Error = Append(target.Smart.Error, $"Windows storage health status: {snapshot.HealthStatus}");
    }

    public static void ApplyReliability(StorageDeviceInfo target, StorageReliabilitySnapshot snapshot)
    {
        target.Smart.Available = snapshot.PowerOnHours.HasValue ||
                                 snapshot.PowerCycleCount.HasValue ||
                                 snapshot.Temperature.HasValue ||
                                 snapshot.Wear.HasValue ||
                                 target.Smart.Available;
        if (target.Smart.Available && target.Smart.Source == "unavailable")
            target.Smart.Source = "Get-StorageReliabilityCounter";
        else if (target.Smart.Available && !target.Smart.Source.Contains("Get-StorageReliabilityCounter", StringComparison.OrdinalIgnoreCase))
            target.Smart.Source += "; Get-StorageReliabilityCounter";

        target.Smart.PowerOnHours ??= snapshot.PowerOnHours;
        target.Smart.PowerCycles ??= snapshot.PowerCycleCount;
        target.Smart.TemperatureCelsius ??= snapshot.Temperature;
        if (snapshot.Wear.HasValue)
            target.Smart.HealthPercent ??= Math.Clamp(100 - snapshot.Wear.Value, 0, 100);
        if (!string.IsNullOrWhiteSpace(snapshot.Error))
            target.Smart.Error = Append(target.Smart.Error, $"Get-StorageReliabilityCounter: {snapshot.Error}");
    }

    private static string Append(string? current, string next)
        => string.IsNullOrWhiteSpace(current) ? next : $"{current}; {next}";

    private static string NormalizeJsonArray(string json)
    {
        var trimmed = json.Trim();
        return trimmed.StartsWith('[') ? trimmed : $"[{trimmed}]";
    }

    private static JsonSerializerOptions JsonOptions() => new() { PropertyNameCaseInsensitive = true };
}

public sealed record StorageReliabilityResult(List<StorageReliabilitySnapshot> Rows, string? Error);

public sealed class PhysicalDiskSnapshot
{
    public string? DeviceId { get; set; }
    public int? DeviceIndex => int.TryParse(DeviceId, out var value) ? value : null;
    public string? FriendlyName { get; set; }
    public string? SerialNumber { get; set; }
    public string? MediaType { get; set; }
    public string? BusType { get; set; }
    public string? HealthStatus { get; set; }
    public string? OperationalStatus { get; set; }
    public ulong? Size { get; set; }
}

public sealed class StorageReliabilitySnapshot
{
    public string? DeviceId { get; set; }
    public int? DeviceIndex => int.TryParse(DeviceId, out var value) ? value : null;
    public string? FriendlyName { get; set; }
    public string? SerialNumber { get; set; }
    public int? PowerOnHours { get; set; }
    public int? PowerCycleCount { get; set; }
    public double? Temperature { get; set; }
    public int? Wear { get; set; }
    public long? ReadErrorsTotal { get; set; }
    public long? WriteErrorsTotal { get; set; }
    public string? Error { get; set; }
}

public sealed class PartitionSnapshot
{
    public int? DiskNumber { get; set; }
    public string? DriveLetter { get; set; }
}
