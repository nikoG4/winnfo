using System.Diagnostics.Eventing.Reader;
using System.Globalization;
using Microsoft.Win32;
using Inspector.Core.Interfaces;
using Inspector.Core.Models;
using Inspector.Infrastructure.ExternalTools;
using Inspector.Infrastructure.Native;
using Inspector.Infrastructure.Parsers;
using Inspector.Infrastructure.Registry;
using Inspector.Infrastructure.Sensors;
using Inspector.Infrastructure.Wmi;

namespace Inspector.Infrastructure.Collectors;

public sealed class IdentityFirmwareOsCollector : IInspectorCollector
{
    public string Name => "Identity/Firmware/OS";

    public Task CollectAsync(InspectionReport report, CancellationToken cancellationToken)
    {
        var computer = Safe(() => WmiQuery.FirstOrEmpty("SELECT * FROM Win32_ComputerSystem"), report);
        var product = Safe(() => WmiQuery.FirstOrEmpty("SELECT * FROM Win32_ComputerSystemProduct"), report);
        var bios = Safe(() => WmiQuery.FirstOrEmpty("SELECT * FROM Win32_BIOS"), report);
        var board = Safe(() => WmiQuery.FirstOrEmpty("SELECT * FROM Win32_BaseBoard"), report);
        var os = Safe(() => WmiQuery.FirstOrEmpty("SELECT * FROM Win32_OperatingSystem"), report);

        report.Identity.Manufacturer = Val(computer.String("Manufacturer"), "WMI Win32_ComputerSystem", "Manufacturer unavailable");
        report.Identity.Model = Val(computer.String("Model"), "WMI Win32_ComputerSystem", "Model unavailable");
        report.Identity.CommercialName = Val(product.String("Name"), "WMI Win32_ComputerSystemProduct", "Commercial name unavailable");
        report.Identity.SerialNumber = Val(bios.String("SerialNumber"), "WMI Win32_BIOS", "Serial unavailable");
        report.Identity.Uuid = Val(product.String("UUID"), "WMI Win32_ComputerSystemProduct", "UUID unavailable");
        report.Identity.DeviceType = Val((computer.Int("PCSystemType") ?? 0) switch { 2 => "Laptop", 1 => "Desktop", 3 => "Workstation", _ => "Unknown" }, "WMI Win32_ComputerSystem", "Device type unavailable");

        report.Firmware.BiosVersion = Val(bios.String("SMBIOSBIOSVersion") ?? bios.String("Version"), "WMI Win32_BIOS", "BIOS version unavailable");
        report.Firmware.BiosDate = DateVal(bios.WmiDate("ReleaseDate"), "WMI Win32_BIOS", "BIOS date unavailable");
        report.Firmware.BiosManufacturer = Val(bios.String("Manufacturer"), "WMI Win32_BIOS", "BIOS manufacturer unavailable");
        report.Firmware.SmbiosVersion = Val($"{bios.Int("SMBIOSMajorVersion")}.{bios.Int("SMBIOSMinorVersion")}", "WMI Win32_BIOS", "SMBIOS unavailable");
        report.Firmware.MotherboardManufacturer = Val(board.String("Manufacturer"), "WMI Win32_BaseBoard", "Board manufacturer unavailable");
        report.Firmware.MotherboardModel = Val(board.String("Product"), "WMI Win32_BaseBoard", "Board model unavailable");
        report.Firmware.BootMode = Val(WindowsRegistryReader.ReadString(RegistryHive.LocalMachine, @"SYSTEM\CurrentControlSet\Control", "PEFirmwareType") switch { "1" => "BIOS/Legacy", "2" => "UEFI", _ => null }, "Registry HKLM SYSTEM", "Boot mode unavailable");
        report.Firmware.SecureBoot = Val(ReadSecureBoot(), "PowerShell Confirm-SecureBootUEFI", "Secure Boot unavailable or Legacy boot");
        report.Firmware.Tpm = Val(ReadTpm(), "WMI root\\CIMV2\\Security\\MicrosoftTpm", "TPM unavailable");

        report.OperatingSystem.Edition = Val(os.String("Caption"), "WMI Win32_OperatingSystem", "OS caption unavailable");
        report.OperatingSystem.Build = Val(os.String("BuildNumber"), "WMI Win32_OperatingSystem", "Build unavailable");
        report.OperatingSystem.Version = Val(os.String("Version"), "WMI Win32_OperatingSystem", "Version unavailable");
        report.OperatingSystem.InstallDate = DateVal(os.WmiDate("InstallDate"), "WMI Win32_OperatingSystem", "Install date unavailable");
        report.OperatingSystem.LastBoot = DateVal(os.WmiDate("LastBootUpTime"), "WMI Win32_OperatingSystem", "Last boot unavailable");
        if (report.OperatingSystem.LastBoot.Value is DateTimeOffset lastBoot)
            report.OperatingSystem.Uptime = new(DateTimeOffset.Now - lastBoot, "derived from WMI LastBootUpTime");
        report.OperatingSystem.Architecture = Val(os.String("OSArchitecture"), "WMI Win32_OperatingSystem", "Architecture unavailable");
        report.OperatingSystem.ActivationStatus = Val(ReadActivation(), "WMI SoftwareLicensingProduct", "Activation unavailable");

        return Task.CompletedTask;
    }

    private static T Safe<T>(Func<T> action, InspectionReport report)
    {
        try { return action(); }
        catch (Exception ex) { report.Issues.Add(new("WMI", "WMI query failed", ex.Message)); return Activator.CreateInstance<T>(); }
    }

    private static InspectionValue<string> Val(string? value, string source, string missing)
        => string.IsNullOrWhiteSpace(value) ? InspectionValue<string>.Missing(source, missing) : new(value.Trim(), source);

    private static InspectionValue<DateTimeOffset> DateVal(DateTimeOffset? value, string source, string missing)
        => value.HasValue ? new(value.Value, source) : InspectionValue<DateTimeOffset>.Missing(source, missing);

    private static string? ReadSecureBoot()
    {
        try
        {
            var result = ProcessRunner.RunAsync("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -Command \"try { Confirm-SecureBootUEFI } catch { 'Unavailable' }\"", TimeSpan.FromSeconds(5), CancellationToken.None).GetAwaiter().GetResult();
            return result.StandardOutput.Trim();
        }
        catch { return null; }
    }

    private static string? ReadTpm()
    {
        try
        {
            var tpm = WmiQuery.FirstOrEmpty("SELECT * FROM Win32_Tpm", @"root\CIMV2\Security\MicrosoftTpm");
            if (tpm.Count == 0) return null;
            return $"Present={tpm.Bool("IsEnabled_InitialValue")}; Version={tpm.String("SpecVersion")}";
        }
        catch { return null; }
    }

    private static string? ReadActivation()
    {
        try
        {
            var rows = WmiQuery.Query("SELECT LicenseStatus,Name FROM SoftwareLicensingProduct WHERE PartialProductKey IS NOT NULL");
            var status = rows.FirstOrDefault()?.Int("LicenseStatus");
            return status switch { 1 => "Licensed", 0 => "Unlicensed", 2 => "OOB grace", 3 => "OOT grace", 4 => "Non-genuine grace", 5 => "Notification", 6 => "Extended grace", _ => null };
        }
        catch { return null; }
    }
}

public sealed class HardwareCollector(HardwareSensorReader sensors) : IInspectorCollector
{
    public string Name => "CPU/RAM/GPU";

    public Task CollectAsync(InspectionReport report, CancellationToken cancellationToken)
    {
        try
        {
            var cpu = WmiQuery.FirstOrEmpty("SELECT * FROM Win32_Processor");
            report.Cpu.Model = Val(cpu.String("Name"), "WMI Win32_Processor", "CPU model unavailable");
            report.Cpu.Cores = IntVal(cpu.Int("NumberOfCores"), "WMI Win32_Processor", "Core count unavailable");
            report.Cpu.Threads = IntVal(cpu.Int("NumberOfLogicalProcessors"), "WMI Win32_Processor", "Thread count unavailable");
            report.Cpu.BaseClockMhz = IntVal(cpu.Int("MaxClockSpeed"), "WMI Win32_Processor", "Base clock unavailable");
            report.Cpu.CurrentClockMhz = IntVal(cpu.Int("CurrentClockSpeed"), "WMI Win32_Processor", "Current clock unavailable");
            report.Cpu.Virtualization = Val(cpu.Bool("VirtualizationFirmwareEnabled")?.ToString(CultureInfo.InvariantCulture), "WMI Win32_Processor", "Virtualization status unavailable");
        }
        catch (Exception ex) { report.Issues.Add(new(Name, "CPU collection failed", ex.Message)); }

        try
        {
            var snapshot = sensors.Read();
            if (snapshot.CpuTemperatureCelsius is > 0)
                report.Cpu.TemperatureCelsius = new(Math.Round(snapshot.CpuTemperatureCelsius.Value, 1), "LibreHardwareMonitor");
            if (snapshot.CpuLoadPercent is > 0)
                report.Cpu.LoadPercent = new(Math.Round(snapshot.CpuLoadPercent.Value, 1), "LibreHardwareMonitor");
            if (!string.IsNullOrWhiteSpace(snapshot.Error))
                report.Issues.Add(new("LibreHardwareMonitor", "Sensor read failed", snapshot.Error, IssueSeverity.Info));
        }
        catch (Exception ex) { report.Issues.Add(new("LibreHardwareMonitor", "Sensor read failed", ex.Message, IssueSeverity.Info)); }

        try
        {
            var modules = WmiQuery.Query("SELECT * FROM Win32_PhysicalMemory");
            report.Memory.Modules = modules.Select(m => new MemoryModuleInfo
            {
                Bank = m.String("BankLabel") ?? m.String("DeviceLocator") ?? "Unknown",
                CapacityBytes = m.ULong("Capacity") ?? 0,
                SpeedMhz = m.Int("Speed") ?? 0,
                MemoryType = DecodeMemoryType(m.Int("SMBIOSMemoryType") ?? m.Int("MemoryType")),
                Manufacturer = m.String("Manufacturer") ?? "Unknown",
                SerialNumber = m.String("SerialNumber") ?? "Unknown"
            }).ToList();
            report.Memory.TotalBytes = new((ulong)report.Memory.Modules.Sum(m => (decimal)m.CapacityBytes), "WMI Win32_PhysicalMemory");
            report.Memory.ModuleCount = new(report.Memory.Modules.Count, "WMI Win32_PhysicalMemory");
            var array = WmiQuery.FirstOrEmpty("SELECT MemoryDevices FROM Win32_PhysicalMemoryArray");
            report.Memory.SlotsTotal = IntVal(array.Int("MemoryDevices"), "WMI Win32_PhysicalMemoryArray", "Slot count unavailable");
            report.Memory.SlotsUsed = new(report.Memory.Modules.Count, "WMI Win32_PhysicalMemory");
        }
        catch (Exception ex) { report.Issues.Add(new(Name, "RAM collection failed", ex.Message)); }

        try
        {
            report.Gpus = WmiQuery.Query("SELECT * FROM Win32_VideoController").Select(g => new GpuInfo
            {
                Name = g.String("Name") ?? "Unknown",
                VramBytes = g.ULong("AdapterRAM"),
                DriverVersion = g.String("DriverVersion") ?? "Unknown",
                DriverDate = g.WmiDate("DriverDate"),
                AdapterType = g.String("VideoProcessor") ?? g.String("AdapterCompatibility") ?? "Unknown"
            }).ToList();

            var sensorSnapshot = sensors.Read();
            foreach (var gpu in report.Gpus)
            {
                var sensor = sensorSnapshot.GpuSensors.FirstOrDefault(s =>
                    gpu.Name.Contains(s.Name, StringComparison.OrdinalIgnoreCase) ||
                    s.Name.Contains(gpu.Name, StringComparison.OrdinalIgnoreCase));
                if (sensor is null) continue;
                gpu.TemperatureCelsius = sensor.TemperatureCelsius;
                gpu.LoadPercent = sensor.LoadPercent;
                gpu.Source += "; LibreHardwareMonitor";
            }
        }
        catch (Exception ex) { report.Issues.Add(new(Name, "GPU collection failed", ex.Message)); }

        return Task.CompletedTask;
    }

    private static string DecodeMemoryType(int? type) => type switch
    {
        20 => "DDR",
        21 => "DDR2",
        24 => "DDR3",
        26 => "DDR4",
        34 => "DDR5",
        _ => "Unknown"
    };

    private static InspectionValue<string> Val(string? value, string source, string missing)
        => string.IsNullOrWhiteSpace(value) ? InspectionValue<string>.Missing(source, missing) : new(value.Trim(), source);

    private static InspectionValue<int> IntVal(int? value, string source, string missing)
        => value.HasValue ? new(value.Value, source) : InspectionValue<int>.Missing(source, missing);
}

public sealed class StorageCollector(SmartctlService smartctl, WindowsStorageService windowsStorage) : IInspectorCollector
{
    public string Name => "Storage";

    public async Task CollectAsync(InspectionReport report, CancellationToken cancellationToken)
    {
        try
        {
            var disks = WmiQuery.Query("SELECT * FROM Win32_DiskDrive");
            var physicalDisks = await windowsStorage.ReadPhysicalDisksAsync(cancellationToken).ConfigureAwait(false);
            var reliability = await windowsStorage.ReadReliabilityAsync(cancellationToken).ConfigureAwait(false);
            var nativeDriveLetters = await windowsStorage.ReadDriveLettersAsync(cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(reliability.Error))
                report.Issues.Add(new("Get-StorageReliabilityCounter", "Native storage reliability query failed", reliability.Error));

            var logicalByDisk = BuildLogicalDiskMap();
            var index = 0;
            foreach (var d in disks)
            {
                var deviceId = d.String("DeviceID") ?? "";
                var physicalIndex = d.Int("Index") ?? index;
                var storage = new StorageDeviceInfo
                {
                    Model = d.String("Model") ?? "Unknown",
                    SerialNumber = d.String("SerialNumber") ?? "Unknown",
                    Firmware = d.String("FirmwareRevision") ?? "Unknown",
                    CapacityBytes = d.ULong("Size"),
                    BusType = d.String("InterfaceType") ?? "Unknown",
                    MediaType = d.String("MediaType") ?? "Unknown"
                };
                if (logicalByDisk.TryGetValue(deviceId, out var letters)) storage.DriveLetters = letters;
                if (storage.DriveLetters.Count == 0 && nativeDriveLetters.TryGetValue(physicalIndex, out var nativeLetters))
                    storage.DriveLetters = nativeLetters;
                storage.Smart = await smartctl.ReadAsync(physicalIndex, storage.Model, storage.SerialNumber, cancellationToken).ConfigureAwait(false);
                var physical = MatchPhysicalDisk(storage, physicalIndex, physicalDisks);
                if (physical is not null)
                    WindowsStorageService.ApplyPhysicalDisk(storage, physical);
                var reliabilityRow = MatchReliability(storage, physicalIndex, reliability.Rows);
                if (reliabilityRow is not null)
                    WindowsStorageService.ApplyReliability(storage, reliabilityRow);
                if (!storage.Smart.Available && !string.IsNullOrWhiteSpace(storage.Smart.Error))
                    report.Issues.Add(new("Storage SMART", $"SMART/reliability unavailable for {storage.Model}", storage.Smart.Error, IssueSeverity.Info));
                report.StorageDevices.Add(storage);
                index++;
            }
        }
        catch (Exception ex)
        {
            report.Issues.Add(new(Name, "Storage collection failed", ex.Message, IssueSeverity.Error));
        }
    }

    private static PhysicalDiskSnapshot? MatchPhysicalDisk(StorageDeviceInfo storage, int physicalIndex, List<PhysicalDiskSnapshot> physicalDisks)
        => physicalDisks.FirstOrDefault(p => p.DeviceIndex == physicalIndex)
           ?? physicalDisks.FirstOrDefault(p => SameSerial(p.SerialNumber, storage.SerialNumber))
           ?? physicalDisks.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p.FriendlyName) && storage.Model.Contains(p.FriendlyName, StringComparison.OrdinalIgnoreCase));

    private static StorageReliabilitySnapshot? MatchReliability(StorageDeviceInfo storage, int physicalIndex, List<StorageReliabilitySnapshot> rows)
        => rows.FirstOrDefault(p => p.DeviceIndex == physicalIndex)
           ?? rows.FirstOrDefault(p => SameSerial(p.SerialNumber, storage.SerialNumber))
           ?? rows.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p.FriendlyName) && storage.Model.Contains(p.FriendlyName, StringComparison.OrdinalIgnoreCase));

    private static bool SameSerial(string? left, string? right)
    {
        static string Clean(string? value) => new((value ?? "").Where(char.IsLetterOrDigit).ToArray());
        var a = Clean(left);
        var b = Clean(right);
        return a.Length > 0 && b.Length > 0 && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    }

    private static Dictionary<string, List<string>> BuildLogicalDiskMap()
    {
        var result = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var searcher = new System.Management.ManagementObjectSearcher("ASSOCIATORS OF {Win32_DiskDrive.DeviceID=''} WHERE AssocClass=Win32_DiskDriveToDiskPartition");
        }
        catch { }

        foreach (var disk in WmiQuery.Query("SELECT DeviceID FROM Win32_DiskDrive"))
        {
            var deviceId = disk.String("DeviceID");
            if (string.IsNullOrWhiteSpace(deviceId)) continue;
            var escaped = deviceId.Replace("\\", "\\\\").Replace("'", "\\'");
            try
            {
                var partitions = WmiQuery.Query($"ASSOCIATORS OF {{Win32_DiskDrive.DeviceID='{escaped}'}} WHERE AssocClass=Win32_DiskDriveToDiskPartition");
                foreach (var partition in partitions)
                {
                    var partitionId = partition.String("DeviceID")?.Replace("\\", "\\\\").Replace("'", "\\'");
                    if (string.IsNullOrWhiteSpace(partitionId)) continue;
                    var logicals = WmiQuery.Query($"ASSOCIATORS OF {{Win32_DiskPartition.DeviceID='{partitionId}'}} WHERE AssocClass=Win32_LogicalDiskToPartition");
                    foreach (var logical in logicals)
                    {
                        var letter = logical.String("DeviceID");
                        if (!string.IsNullOrWhiteSpace(letter))
                        {
                            if (!result.ContainsKey(deviceId)) result[deviceId] = [];
                            result[deviceId].Add(letter);
                        }
                    }
                }
            }
            catch { }
        }
        return result;
    }
}

public sealed class BatteryCollector : IInspectorCollector
{
    public string Name => "Battery";

    public async Task CollectAsync(InspectionReport report, CancellationToken cancellationToken)
    {
        try
        {
            var batteries = WmiQuery.Query("SELECT * FROM Win32_Battery");
            if (batteries.Count == 0)
            {
                report.Battery = null;
                return;
            }

            var output = Path.Combine(Path.GetTempPath(), $"whui-battery-{Guid.NewGuid():N}.html");
            var result = await ProcessRunner.RunAsync("powercfg.exe", $"/batteryreport /output \"{output}\"", TimeSpan.FromSeconds(20), cancellationToken).ConfigureAwait(false);
            BatteryInfo battery;
            if (File.Exists(output))
                battery = BatteryReportParser.Parse(output);
            else
                battery = new BatteryInfo { BatteryReportPath = output };

            var status = batteries.First().Int("BatteryStatus") switch
            {
                1 => "Discharging",
                2 => "AC",
                3 => "Fully charged",
                4 => "Low",
                5 => "Critical",
                6 => "Charging",
                _ => "Unknown"
            };
            battery.CurrentStatus = new(status, "WMI Win32_Battery");
            if (result.ExitCode != 0)
                report.Issues.Add(new(Name, "powercfg batteryreport returned non-zero", result.StandardError));
            report.Battery = battery;
        }
        catch (Exception ex)
        {
            report.Issues.Add(new(Name, "Battery collection failed", ex.Message));
        }
    }
}

public sealed class UsageHistoryCollector : IInspectorCollector
{
    public string Name => "Usage history";

    public Task CollectAsync(InspectionReport report, CancellationToken cancellationToken)
    {
        try
        {
            var ids = new[] { 12, 13, 41, 42, 107, 6005, 6006, 6008 };
            var query = new EventLogQuery("System", PathType.LogName, "*[System[(" + string.Join(" or ", ids.Select(id => $"EventID={id}")) + ")]]")
            {
                ReverseDirection = true
            };
            using var reader = new EventLogReader(query);
            var count = 0;
            DateTimeOffset? newest = null;
            DateTimeOffset? oldest = null;
            for (EventRecord? record = reader.ReadEvent(); record is not null && count < 2000; record = reader.ReadEvent())
            {
                cancellationToken.ThrowIfCancellationRequested();
                count++;
                var t = record.TimeCreated.HasValue ? new DateTimeOffset(record.TimeCreated.Value) : (DateTimeOffset?)null;
                newest ??= t;
                oldest = t ?? oldest;
                switch (record.Id)
                {
                    case 12:
                    case 6005: report.UsageHistory.BootEvents++; break;
                    case 13:
                    case 6006: report.UsageHistory.ShutdownEvents++; break;
                    case 41:
                    case 6008: report.UsageHistory.UnexpectedShutdowns++; break;
                    case 42: report.UsageHistory.SleepEvents++; break;
                    case 107: report.UsageHistory.ResumeEvents++; break;
                }
                record.Dispose();
            }
            report.UsageHistory.OldestEvent = oldest;
            report.UsageHistory.NewestEvent = newest;
            report.UsageHistory.ApproximateSessions = Math.Max(report.UsageHistory.BootEvents, report.UsageHistory.ResumeEvents);
            if (oldest.HasValue && newest.HasValue && newest > oldest)
                report.UsageHistory.EventsPerDay = Math.Round(count / Math.Max(1, (newest.Value - oldest.Value).TotalDays), 2);
        }
        catch (Exception ex)
        {
            report.Issues.Add(new(Name, "Event log collection failed", ex.Message));
        }
        return Task.CompletedTask;
    }
}

public sealed class NetworkDeviceCollector : IInspectorCollector
{
    public string Name => "Network/devices";

    public Task CollectAsync(InspectionReport report, CancellationToken cancellationToken)
    {
        try
        {
            report.NetworkAndDevices.NetworkAdapters = WmiQuery.Query("SELECT * FROM Win32_NetworkAdapter WHERE MACAddress IS NOT NULL")
                .Select(n => new NetworkAdapterInfo
                {
                    Name = n.String("Name") ?? "",
                    MacAddress = n.String("MACAddress") ?? "",
                    AdapterType = n.String("AdapterType") ?? "",
                    PhysicalAdapter = n.Bool("PhysicalAdapter") ?? false,
                    NetConnectionStatus = DecodeNetStatus(n.Int("NetConnectionStatus"))
                }).ToList();

            report.NetworkAndDevices.ProblemDevices = WmiQuery.Query("SELECT * FROM Win32_PnPEntity WHERE ConfigManagerErrorCode <> 0")
                .Select(d => new DeviceProblemInfo
                {
                    Name = d.String("Name") ?? "",
                    DeviceId = d.String("DeviceID") ?? "",
                    Status = d.String("Status") ?? "",
                    ConfigManagerErrorCode = d.UInt("ConfigManagerErrorCode")
                }).ToList();
        }
        catch (Exception ex) { report.Issues.Add(new(Name, "Network/device collection failed", ex.Message)); }
        return Task.CompletedTask;
    }

    private static string DecodeNetStatus(int? status) => status switch
    {
        2 => "Connected",
        7 => "Media disconnected",
        0 => "Disconnected",
        _ => status?.ToString(CultureInfo.InvariantCulture) ?? "Unknown"
    };
}
