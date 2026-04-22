using System.Net;
using System.Text;
using Inspector.Core.Interfaces;
using Inspector.Core.Models;

namespace Inspector.Core.Reporting;

public sealed class HtmlReportExporter : IReportExporter
{
    public string Format => "HTML";

    public async Task ExportAsync(InspectionReport report, string path, CancellationToken cancellationToken = default)
    {
        var html = Build(report);
        await File.WriteAllTextAsync(path, html, Encoding.UTF8, cancellationToken).ConfigureAwait(false);
    }

    private static string Build(InspectionReport r)
    {
        var b = new StringBuilder();
        b.AppendLine("<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">");
        b.AppendLine("<title>Windows Hardware Usage Inspector</title>");
        b.AppendLine("<style>body{font-family:Segoe UI,Arial,sans-serif;margin:0;color:#17202a;background:#f5f7fa}header{background:#12263a;color:white;padding:28px 36px}main{padding:24px 36px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}.card{background:white;border:1px solid #d9e2ec;border-radius:8px;padding:16px;margin-bottom:16px}h1,h2{margin:0 0 12px}table{width:100%;border-collapse:collapse;background:white}td,th{padding:8px 10px;border-bottom:1px solid #e6edf3;text-align:left}.score{font-size:36px;font-weight:700}.warn{color:#9a6700}.err{color:#b42318}.ok{color:#067647}.muted{color:#5d6d7e}</style></head><body>");
        b.AppendLine($"<header><h1>Windows Hardware Usage Inspector</h1><p>{E(r.Identity.Manufacturer.Value)} {E(r.Identity.Model.Value)} - {E(r.Identity.ComputerName.Value)}</p></header><main>");
        b.AppendLine("<section class=\"grid\">");
        b.AppendLine(Card("Uso estimado", $"{r.Diagnostic.UsageScore:0.0}", r.Diagnostic.UsageLevel.ToString()));
        b.AppendLine(Card("Estado general", $"{r.Diagnostic.ConditionScore:0.0}", r.Diagnostic.ConditionLevel.ToString()));
        b.AppendLine(Card("Confianza", r.Diagnostic.Confidence.ToString(), r.Diagnostic.Summary));
        b.AppendLine("</section>");

        Section(b, "Identidad", Rows(("Fabricante", r.Identity.Manufacturer), ("Modelo", r.Identity.Model), ("Serial", r.Identity.SerialNumber), ("UUID", r.Identity.Uuid), ("Tipo", r.Identity.DeviceType)));
        Section(b, "Firmware", Rows(("BIOS", r.Firmware.BiosVersion), ("Fecha BIOS", r.Firmware.BiosDate), ("SMBIOS", r.Firmware.SmbiosVersion), ("Placa", r.Firmware.MotherboardModel), ("Secure Boot", r.Firmware.SecureBoot), ("TPM", r.Firmware.Tpm)));
        Section(b, "Sistema operativo", Rows(("Edición", r.OperatingSystem.Edition), ("Build", r.OperatingSystem.Build), ("Versión", r.OperatingSystem.Version), ("Instalación", r.OperatingSystem.InstallDate), ("Último arranque", r.OperatingSystem.LastBoot), ("Uptime", r.OperatingSystem.Uptime)));
        Section(b, "CPU y RAM", Rows(("CPU", r.Cpu.Model), ("Nucleos", r.Cpu.Cores), ("Hilos", r.Cpu.Threads), ("RAM total", FormatBytes(r.Memory.TotalBytes.Value)), ("Modulos", r.Memory.ModuleCount)));

        b.AppendLine("<section class=\"card\"><h2>Almacenamiento</h2><table><tr><th>Modelo</th><th>Serial</th><th>Capacidad</th><th>Bus</th><th>Horas</th><th>Encendidos</th><th>Salud</th><th>Escritura GB</th><th>Fuente</th></tr>");
        foreach (var d in r.StorageDevices)
            b.AppendLine($"<tr><td>{E(d.Model)}</td><td>{E(d.SerialNumber)}</td><td>{FormatBytes(d.CapacityBytes)}</td><td>{E(d.BusType)}</td><td>{d.Smart.PowerOnHours}</td><td>{d.Smart.PowerCycles}</td><td>{d.Smart.HealthPercent}</td><td>{d.Smart.TotalHostWritesGb:0.##}</td><td>{E(d.Smart.Source)}</td></tr>");
        b.AppendLine("</table></section>");

        if (r.Battery is not null)
            Section(b, "Batería", Rows(("Fabricante", r.Battery.Manufacturer), ("Química", r.Battery.Chemistry), ("Design capacity", r.Battery.DesignCapacityMwh), ("Full charge", r.Battery.FullChargeCapacityMwh), ("Wear %", r.Battery.WearLevelPercent), ("Ciclos", r.Battery.CycleCount), ("Estado", r.Battery.CurrentStatus)));

        b.AppendLine("<section class=\"card\"><h2>Alertas</h2>");
        if (r.Diagnostic.Alerts.Count == 0) b.AppendLine("<p class=\"ok\">No se detectaron alertas fuertes.</p>");
        foreach (var a in r.Diagnostic.Alerts)
            b.AppendLine($"<p class=\"{(a.Severity == IssueSeverity.Error ? "err" : "warn")}\"><strong>{E(a.Code)}</strong>: {E(a.Message)}</p>");
        b.AppendLine("</section>");

        b.AppendLine("</main></body></html>");
        return b.ToString();
    }

    private static string Card(string title, string value, string detail) => $"<article class=\"card\"><h2>{E(title)}</h2><div class=\"score\">{E(value)}</div><p class=\"muted\">{E(detail)}</p></article>";

    private static void Section(StringBuilder b, string title, string rows)
        => b.AppendLine($"<section class=\"card\"><h2>{E(title)}</h2><table>{rows}</table></section>");

    private static string Rows(params (string Label, object? Value)[] rows)
        => string.Join("", rows.Select(r => $"<tr><th>{E(r.Label)}</th><td>{E(FormatObj(r.Value))}</td></tr>"));

    private static string FormatObj(object? value)
    {
        if (value is null) return "N/D";
        var type = value.GetType();
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(InspectionValue<>))
        {
            var v = type.GetProperty("Value")?.GetValue(value);
            var available = (bool)(type.GetProperty("IsAvailable")?.GetValue(value) ?? false);
            var source = type.GetProperty("Source")?.GetValue(value);
            var note = type.GetProperty("Note")?.GetValue(value);
            return available ? $"{v ?? "N/D"} ({source})" : $"N/D - {note} ({source})";
        }
        return value.ToString() ?? "N/D";
    }

    private static string FormatBytes(ulong? bytes)
    {
        if (bytes is null or 0) return "N/D";
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var value = (double)bytes.Value;
        var index = 0;
        while (value >= 1024 && index < units.Length - 1) { value /= 1024; index++; }
        return $"{value:0.##} {units[index]}";
    }

    private static string E(object? value) => WebUtility.HtmlEncode(value?.ToString() ?? "N/D");
}
