using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows.Input;
using Inspector.Core.Interfaces;
using Inspector.Core.Models;
using Microsoft.Win32;

namespace Inspector.App.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private readonly IInspectionOrchestrator _orchestrator;
    private readonly IEnumerable<IReportExporter> _exporters;
    private InspectionReport? _report;
    private string _status = "Ready.";

    public MainViewModel(IInspectionOrchestrator orchestrator, IEnumerable<IReportExporter> exporters)
    {
        _orchestrator = orchestrator;
        _exporters = exporters;
        RefreshCommand = new AsyncCommand(RefreshAsync);
        ExportJsonCommand = new AsyncCommand(() => ExportAsync("JSON"), () => Report is not null);
        ExportHtmlCommand = new AsyncCommand(() => ExportAsync("HTML"), () => Report is not null);
    }

    public InspectionReport? Report
    {
        get => _report;
        private set
        {
            if (SetProperty(ref _report, value))
                RefreshDerived();
        }
    }

    public string Status { get => _status; set => SetProperty(ref _status, value); }
    public ICommand RefreshCommand { get; }
    public ICommand ExportJsonCommand { get; }
    public ICommand ExportHtmlCommand { get; }

    public string HeaderSummary => Report is null ? T("HeaderNoInspection") : $"{Report.Identity.Manufacturer.Value} {Report.Identity.Model.Value} - {Report.Identity.SerialNumber.Value}";
    public string UsageScore => Report is null ? "-" : $"{Report.Diagnostic.UsageScore:0.0}";
    public string UsageLevel => Report?.Diagnostic.UsageLevel.ToString() ?? "-";
    public string ConditionScore => Report is null ? "-" : $"{Report.Diagnostic.ConditionScore:0.0}";
    public string ConditionLevel => Report?.Diagnostic.ConditionLevel.ToString() ?? "-";
    public string Confidence => Report?.Diagnostic.Confidence.ToString() ?? "-";
    public string DiagnosticSummary => Report?.Diagnostic.Summary ?? "";
    public string Footer => Report is null ? "" : string.Format(CultureInfo.CurrentCulture, T("FooterGenerated"), Report.GeneratedAt, Report.Issues.Count);

    public ObservableCollection<Row> SystemRows { get; } = [];
    public ObservableCollection<Row> HardwareRows { get; } = [];
    public ObservableCollection<Row> GpuRows { get; } = [];
    public ObservableCollection<StorageRow> StorageRows { get; } = [];
    public ObservableCollection<Row> BatteryRows { get; } = [];
    public ObservableCollection<Row> HistoryRows { get; } = [];
    public ObservableCollection<Row> NetworkRows { get; } = [];
    public ObservableCollection<Row> ProblemDeviceRows { get; } = [];
    public ObservableCollection<string> Alerts { get; } = [];
    public ObservableCollection<ScoreContribution> UsageContributions { get; } = [];
    public ObservableCollection<ScoreContribution> ConditionContributions { get; } = [];

    public async Task RefreshAsync()
    {
        Status = T("StatusCollecting");
        try
        {
            Report = await _orchestrator.RunAsync();
            Status = T("StatusCompleted");
        }
        catch (Exception ex)
        {
            Status = $"{T("StatusError")}: {ex.Message}";
        }
    }

    private async Task ExportAsync(string format)
    {
        if (Report is null) return;
        var exporter = _exporters.First(e => e.Format == format);
        var dialog = new SaveFileDialog
        {
            Title = string.Format(CultureInfo.CurrentCulture, T("ExportTitle"), format),
            FileName = $"hardware-usage-report-{DateTime.Now:yyyyMMdd-HHmmss}.{format.ToLowerInvariant()}",
            Filter = format == "JSON" ? "JSON (*.json)|*.json" : "HTML (*.html)|*.html"
        };
        if (dialog.ShowDialog() != true) return;
        await exporter.ExportAsync(Report, dialog.FileName);
        Status = string.Format(CultureInfo.CurrentCulture, T("ExportedStatus"), format, dialog.FileName);
    }

    private void RefreshDerived()
    {
        ClearAll();
        if (Report is null) return;
        var r = Report;

        Add(SystemRows, T("Manufacturer"), r.Identity.Manufacturer);
        Add(SystemRows, T("Model"), r.Identity.Model);
        Add(SystemRows, T("CommercialName"), r.Identity.CommercialName);
        Add(SystemRows, T("Serial"), r.Identity.SerialNumber);
        Add(SystemRows, "UUID", r.Identity.Uuid);
        Add(SystemRows, T("DeviceType"), r.Identity.DeviceType);
        Add(SystemRows, "BIOS", r.Firmware.BiosVersion);
        Add(SystemRows, T("BiosDate"), r.Firmware.BiosDate, SignalKind.Age);
        Add(SystemRows, "SMBIOS", r.Firmware.SmbiosVersion);
        Add(SystemRows, T("Motherboard"), r.Firmware.MotherboardModel);
        Add(SystemRows, T("BootMode"), r.Firmware.BootMode);
        Add(SystemRows, "Secure Boot", r.Firmware.SecureBoot);
        Add(SystemRows, "TPM", r.Firmware.Tpm);
        Add(SystemRows, "Windows", r.OperatingSystem.Edition);
        Add(SystemRows, "Build", r.OperatingSystem.Build);
        Add(SystemRows, T("InstallDate"), r.OperatingSystem.InstallDate, SignalKind.Age);
        Add(SystemRows, T("LastBoot"), r.OperatingSystem.LastBoot, SignalKind.Usage);
        Add(SystemRows, "Uptime", r.OperatingSystem.Uptime, SignalKind.Usage);
        Add(SystemRows, T("Activation"), r.OperatingSystem.ActivationStatus);

        Add(HardwareRows, "CPU", r.Cpu.Model);
        Add(HardwareRows, T("Cores"), r.Cpu.Cores);
        Add(HardwareRows, T("Threads"), r.Cpu.Threads);
        Add(HardwareRows, T("BaseClock"), r.Cpu.BaseClockMhz);
        Add(HardwareRows, T("CurrentClock"), r.Cpu.CurrentClockMhz, SignalKind.Usage);
        Add(HardwareRows, T("Virtualization"), r.Cpu.Virtualization);
        Add(HardwareRows, T("CpuTemperature"), r.Cpu.TemperatureCelsius, SignalKind.Health);
        Add(HardwareRows, T("CpuLoad"), r.Cpu.LoadPercent, SignalKind.Usage);
        Add(HardwareRows, T("RamTotal"), FormatBytes(r.Memory.TotalBytes.Value), r.Memory.TotalBytes.Source);
        Add(HardwareRows, T("RamModules"), r.Memory.ModuleCount);
        Add(HardwareRows, T("SlotsUsed"), r.Memory.SlotsUsed);
        Add(HardwareRows, T("SlotsTotal"), r.Memory.SlotsTotal);
        foreach (var m in r.Memory.Modules)
            Add(HardwareRows, $"RAM {m.Bank}", $"{FormatBytes(m.CapacityBytes)} {m.SpeedMhz} MHz {m.MemoryType} {m.Manufacturer} SN:{m.SerialNumber}", m.Source);

        foreach (var g in r.Gpus)
            GpuRows.Add(new(g.Name, $"{FormatBytes(g.VramBytes)}; Temp={g.TemperatureCelsius?.ToString("0.#", CultureInfo.CurrentCulture) ?? "N/D"} C; Load={g.LoadPercent?.ToString("0.#", CultureInfo.CurrentCulture) ?? "N/D"}%", $"{g.DriverVersion} - {g.Source}", SignalKind.Usage));

        foreach (var d in r.StorageDevices)
            StorageRows.Add(new(
                d.Model,
                d.SerialNumber,
                FormatBytes(d.CapacityBytes),
                d.BusType,
                string.Join(", ", d.DriveLetters),
                d.Smart.PowerOnHours?.ToString(CultureInfo.CurrentCulture) ?? "N/D",
                d.Smart.PowerCycles?.ToString(CultureInfo.CurrentCulture) ?? "N/D",
                d.Smart.HealthPercent?.ToString(CultureInfo.CurrentCulture) ?? "N/D",
                d.Smart.TotalHostWritesGb?.ToString("0.##", CultureInfo.CurrentCulture) ?? "N/D",
                d.Smart.Source,
                d.Smart.PowerOnHours is >= 4500 ? SignalKind.Warning : SignalKind.Usage,
                d.Smart.PowerCycles is >= 1200 ? SignalKind.Warning : SignalKind.Usage,
                d.Smart.HealthPercent is <= 80 ? SignalKind.Warning : SignalKind.Health,
                d.Smart.TotalHostWritesGb is >= 25000 ? SignalKind.Warning : SignalKind.Usage));

        if (r.Battery is null)
        {
            BatteryRows.Add(new(T("Battery"), T("NotDetected"), "WMI Win32_Battery", SignalKind.Normal));
        }
        else
        {
            Add(BatteryRows, T("Manufacturer"), r.Battery.Manufacturer);
            Add(BatteryRows, T("Chemistry"), r.Battery.Chemistry);
            Add(BatteryRows, "Design capacity mWh", r.Battery.DesignCapacityMwh);
            Add(BatteryRows, "Full charge mWh", r.Battery.FullChargeCapacityMwh);
            Add(BatteryRows, "Wear %", r.Battery.WearLevelPercent, SignalKind.Health);
            Add(BatteryRows, T("Cycles"), r.Battery.CycleCount, SignalKind.Usage);
            Add(BatteryRows, T("Status"), r.Battery.CurrentStatus);
            Add(BatteryRows, "Battery report", r.Battery.BatteryReportPath ?? "N/D", "powercfg");
        }

        Add(HistoryRows, T("Boots"), r.UsageHistory.BootEvents.ToString(CultureInfo.CurrentCulture), r.UsageHistory.Source, SignalKind.Usage);
        Add(HistoryRows, T("Shutdowns"), r.UsageHistory.ShutdownEvents.ToString(CultureInfo.CurrentCulture), r.UsageHistory.Source, SignalKind.Usage);
        Add(HistoryRows, T("UnexpectedShutdowns"), r.UsageHistory.UnexpectedShutdowns.ToString(CultureInfo.CurrentCulture), r.UsageHistory.Source, r.UsageHistory.UnexpectedShutdowns > 0 ? SignalKind.Warning : SignalKind.Usage);
        Add(HistoryRows, T("SleepEvents"), r.UsageHistory.SleepEvents.ToString(CultureInfo.CurrentCulture), r.UsageHistory.Source, SignalKind.Usage);
        Add(HistoryRows, T("ResumeEvents"), r.UsageHistory.ResumeEvents.ToString(CultureInfo.CurrentCulture), r.UsageHistory.Source, SignalKind.Usage);
        Add(HistoryRows, T("ApproxSessions"), r.UsageHistory.ApproximateSessions.ToString(CultureInfo.CurrentCulture), r.UsageHistory.Source, SignalKind.Usage);
        Add(HistoryRows, T("EventsPerDay"), r.UsageHistory.EventsPerDay.ToString("0.##", CultureInfo.CurrentCulture), r.UsageHistory.Source, SignalKind.Usage);

        foreach (var n in r.NetworkAndDevices.NetworkAdapters)
            NetworkRows.Add(new(n.Name, n.MacAddress, $"{n.AdapterType}; {n.NetConnectionStatus}; Physical={n.PhysicalAdapter}", SignalKind.Normal));
        foreach (var d in r.NetworkAndDevices.ProblemDevices)
            ProblemDeviceRows.Add(new(d.Name, $"{d.Status}; Code={d.ConfigManagerErrorCode}", d.Source, SignalKind.Warning));

        foreach (var a in r.Diagnostic.Alerts)
            Alerts.Add($"{a.Severity}: {a.Message}");
        foreach (var i in r.Issues)
            Alerts.Add($"{i.Severity}: {i.Source} - {i.Message}: {i.Detail}");
        if (Alerts.Count == 0) Alerts.Add(T("NoAlerts"));

        foreach (var c in r.Diagnostic.UsageContributions) UsageContributions.Add(c);
        foreach (var c in r.Diagnostic.ConditionContributions) ConditionContributions.Add(c);

        NotifySummary();
    }

    private void ClearAll()
    {
        SystemRows.Clear();
        HardwareRows.Clear();
        GpuRows.Clear();
        StorageRows.Clear();
        BatteryRows.Clear();
        HistoryRows.Clear();
        NetworkRows.Clear();
        ProblemDeviceRows.Clear();
        Alerts.Clear();
        UsageContributions.Clear();
        ConditionContributions.Clear();
    }

    private void NotifySummary()
    {
        OnPropertyChanged(nameof(HeaderSummary));
        OnPropertyChanged(nameof(UsageScore));
        OnPropertyChanged(nameof(UsageLevel));
        OnPropertyChanged(nameof(ConditionScore));
        OnPropertyChanged(nameof(ConditionLevel));
        OnPropertyChanged(nameof(Confidence));
        OnPropertyChanged(nameof(DiagnosticSummary));
        OnPropertyChanged(nameof(Footer));
    }

    private static void Add<T>(ObservableCollection<Row> rows, string name, InspectionValue<T> value, SignalKind kind = SignalKind.Normal)
        => rows.Add(new(name, value.IsAvailable ? FormatValue(value.Value) : $"N/D ({value.Note})", value.Source, kind));

    private static void Add(ObservableCollection<Row> rows, string name, string value, string source, SignalKind kind = SignalKind.Normal)
        => rows.Add(new(name, value, source, kind));

    private static string FormatValue(object? value)
        => value switch
        {
            null => "N/D",
            ulong bytes when bytes > 1024 * 1024 => FormatBytes(bytes),
            TimeSpan span => $"{span.Days}d {span.Hours}h {span.Minutes}m",
            DateTimeOffset date => date.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.CurrentCulture),
            double number => number.ToString("0.##", CultureInfo.CurrentCulture),
            _ => value.ToString() ?? "N/D"
        };

    private static string FormatBytes(ulong? bytes)
    {
        if (bytes is null or 0) return "N/D";
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var value = (double)bytes.Value;
        var index = 0;
        while (value >= 1024 && index < units.Length - 1) { value /= 1024; index++; }
        return $"{value:0.##} {units[index]}";
    }

    private static string T(string key) => System.Windows.Application.Current.TryFindResource(key)?.ToString() ?? key;
}

public enum SignalKind
{
    Normal,
    Usage,
    Age,
    Health,
    Warning
}

public sealed record Row(string Name, string Value, string Source, SignalKind Kind);

public sealed record StorageRow(
    string Model,
    string Serial,
    string Capacity,
    string Bus,
    string Drives,
    string PowerOnHours,
    string PowerCycles,
    string Health,
    string WritesGb,
    string SmartSource,
    SignalKind PowerOnHoursKind,
    SignalKind PowerCyclesKind,
    SignalKind HealthKind,
    SignalKind WritesKind);
