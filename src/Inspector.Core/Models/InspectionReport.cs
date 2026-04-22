namespace Inspector.Core.Models;

public sealed class InspectionReport
{
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.Now;
    public ComputerIdentity Identity { get; set; } = new();
    public FirmwareInfo Firmware { get; set; } = new();
    public OperatingSystemInfo OperatingSystem { get; set; } = new();
    public CpuInfo Cpu { get; set; } = new();
    public MemoryInfo Memory { get; set; } = new();
    public List<GpuInfo> Gpus { get; set; } = [];
    public List<StorageDeviceInfo> StorageDevices { get; set; } = [];
    public BatteryInfo? Battery { get; set; }
    public UsageHistoryInfo UsageHistory { get; set; } = new();
    public NetworkAndDeviceInfo NetworkAndDevices { get; set; } = new();
    public DiagnosticResult Diagnostic { get; set; } = new();
    public List<CollectionIssue> Issues { get; set; } = [];
}

public sealed class ComputerIdentity
{
    public InspectionValue<string> Manufacturer { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> Model { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> CommercialName { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> SerialNumber { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> Uuid { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> ComputerName { get; set; } = new(Environment.MachineName, ".NET Environment");
    public InspectionValue<string> DeviceType { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
}

public sealed class FirmwareInfo
{
    public InspectionValue<string> BiosVersion { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<DateTimeOffset> BiosDate { get; set; } = InspectionValue<DateTimeOffset>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> BiosManufacturer { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> SmbiosVersion { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> MotherboardManufacturer { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> MotherboardModel { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> BootMode { get; set; } = InspectionValue<string>.Missing("registry", "Not collected");
    public InspectionValue<string> SecureBoot { get; set; } = InspectionValue<string>.Missing("PowerShell", "Not collected");
    public InspectionValue<string> Tpm { get; set; } = InspectionValue<string>.Missing("WMI", "Not collected");
}

public sealed class OperatingSystemInfo
{
    public InspectionValue<string> Edition { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> Build { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> Version { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<DateTimeOffset> InstallDate { get; set; } = InspectionValue<DateTimeOffset>.Missing("not-collected", "Pending collection");
    public InspectionValue<DateTimeOffset> LastBoot { get; set; } = InspectionValue<DateTimeOffset>.Missing("not-collected", "Pending collection");
    public InspectionValue<TimeSpan> Uptime { get; set; } = InspectionValue<TimeSpan>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> Architecture { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> ActivationStatus { get; set; } = InspectionValue<string>.Missing("WMI", "Not collected");
}

public sealed class CpuInfo
{
    public InspectionValue<string> Model { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<int> Cores { get; set; } = InspectionValue<int>.Missing("not-collected", "Pending collection");
    public InspectionValue<int> Threads { get; set; } = InspectionValue<int>.Missing("not-collected", "Pending collection");
    public InspectionValue<int> BaseClockMhz { get; set; } = InspectionValue<int>.Missing("not-collected", "Pending collection");
    public InspectionValue<int> CurrentClockMhz { get; set; } = InspectionValue<int>.Missing("not-collected", "Pending collection");
    public InspectionValue<string> Virtualization { get; set; } = InspectionValue<string>.Missing("not-collected", "Pending collection");
    public InspectionValue<double> TemperatureCelsius { get; set; } = InspectionValue<double>.Missing("sensors", "Sensor not available");
    public InspectionValue<double> LoadPercent { get; set; } = InspectionValue<double>.Missing("performance counter", "Not collected");
}

public sealed class MemoryInfo
{
    public InspectionValue<ulong> TotalBytes { get; set; } = InspectionValue<ulong>.Missing("not-collected", "Pending collection");
    public InspectionValue<int> ModuleCount { get; set; } = InspectionValue<int>.Missing("not-collected", "Pending collection");
    public InspectionValue<int> SlotsUsed { get; set; } = InspectionValue<int>.Missing("WMI", "Not collected");
    public InspectionValue<int> SlotsTotal { get; set; } = InspectionValue<int>.Missing("WMI", "Not collected");
    public List<MemoryModuleInfo> Modules { get; set; } = [];
}

public sealed class MemoryModuleInfo
{
    public string Bank { get; set; } = "";
    public ulong CapacityBytes { get; set; }
    public int SpeedMhz { get; set; }
    public string MemoryType { get; set; } = "Unknown";
    public string Manufacturer { get; set; } = "Unknown";
    public string SerialNumber { get; set; } = "Unknown";
    public string Source { get; set; } = "WMI Win32_PhysicalMemory";
}

public sealed class GpuInfo
{
    public string Name { get; set; } = "Unknown";
    public ulong? VramBytes { get; set; }
    public string DriverVersion { get; set; } = "Unknown";
    public DateTimeOffset? DriverDate { get; set; }
    public string AdapterType { get; set; } = "Unknown";
    public double? TemperatureCelsius { get; set; }
    public double? LoadPercent { get; set; }
    public string Source { get; set; } = "WMI Win32_VideoController";
}

public sealed class StorageDeviceInfo
{
    public string Model { get; set; } = "Unknown";
    public string SerialNumber { get; set; } = "Unknown";
    public string Firmware { get; set; } = "Unknown";
    public ulong? CapacityBytes { get; set; }
    public string BusType { get; set; } = "Unknown";
    public string MediaType { get; set; } = "Unknown";
    public List<string> Partitions { get; set; } = [];
    public List<string> DriveLetters { get; set; } = [];
    public SmartInfo Smart { get; set; } = new();
    public string Source { get; set; } = "WMI Win32_DiskDrive";
}

public sealed class SmartInfo
{
    public bool Available { get; set; }
    public string Source { get; set; } = "unavailable";
    public int? PowerOnHours { get; set; }
    public int? PowerCycles { get; set; }
    public int? HealthPercent { get; set; }
    public double? TemperatureCelsius { get; set; }
    public double? TotalHostWritesGb { get; set; }
    public int? UnsafeShutdowns { get; set; }
    public string? RawJson { get; set; }
    public string? Error { get; set; }
}

public sealed class BatteryInfo
{
    public InspectionValue<string> Manufacturer { get; set; } = InspectionValue<string>.Missing("battery report", "Not collected");
    public InspectionValue<string> Chemistry { get; set; } = InspectionValue<string>.Missing("battery report", "Not collected");
    public InspectionValue<int> DesignCapacityMwh { get; set; } = InspectionValue<int>.Missing("battery report", "Not collected");
    public InspectionValue<int> FullChargeCapacityMwh { get; set; } = InspectionValue<int>.Missing("battery report", "Not collected");
    public InspectionValue<double> WearLevelPercent { get; set; } = InspectionValue<double>.Missing("battery report", "Not collected");
    public InspectionValue<int> CycleCount { get; set; } = InspectionValue<int>.Missing("battery report", "Not collected");
    public InspectionValue<string> CurrentStatus { get; set; } = InspectionValue<string>.Missing("WMI", "Not collected");
    public string? BatteryReportPath { get; set; }
    public List<string> Inferences { get; set; } = [];
}

public sealed class UsageHistoryInfo
{
    public int BootEvents { get; set; }
    public int ShutdownEvents { get; set; }
    public int UnexpectedShutdowns { get; set; }
    public int SleepEvents { get; set; }
    public int ResumeEvents { get; set; }
    public int ApproximateSessions { get; set; }
    public double EventsPerDay { get; set; }
    public DateTimeOffset? OldestEvent { get; set; }
    public DateTimeOffset? NewestEvent { get; set; }
    public string Source { get; set; } = "Windows Event Log";
}

public sealed class NetworkAndDeviceInfo
{
    public List<NetworkAdapterInfo> NetworkAdapters { get; set; } = [];
    public List<DeviceProblemInfo> ProblemDevices { get; set; } = [];
}

public sealed class NetworkAdapterInfo
{
    public string Name { get; set; } = "";
    public string MacAddress { get; set; } = "";
    public string AdapterType { get; set; } = "";
    public bool PhysicalAdapter { get; set; }
    public string NetConnectionStatus { get; set; } = "";
    public string Source { get; set; } = "WMI Win32_NetworkAdapter";
}

public sealed class DeviceProblemInfo
{
    public string Name { get; set; } = "";
    public string DeviceId { get; set; } = "";
    public string Status { get; set; } = "";
    public uint? ConfigManagerErrorCode { get; set; }
    public string Source { get; set; } = "WMI Win32_PnPEntity";
}

public sealed class DiagnosticResult
{
    public double UsageScore { get; set; }
    public double ConditionScore { get; set; }
    public UsageLevel UsageLevel { get; set; }
    public ConditionLevel ConditionLevel { get; set; }
    public ConfidenceLevel Confidence { get; set; }
    public List<ScoreContribution> UsageContributions { get; set; } = [];
    public List<ScoreContribution> ConditionContributions { get; set; } = [];
    public List<DiagnosticAlert> Alerts { get; set; } = [];
    public string Summary { get; set; } = "";
}

public sealed record ScoreContribution(string Signal, double RawValue, double Weight, double NormalizedScore, string Source, string Note);
