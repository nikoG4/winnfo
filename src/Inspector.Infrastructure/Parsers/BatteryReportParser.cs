using System.Text.RegularExpressions;
using Inspector.Core.Models;

namespace Inspector.Infrastructure.Parsers;

internal static partial class BatteryReportParser
{
    public static BatteryInfo Parse(string htmlPath)
    {
        var text = File.ReadAllText(htmlPath);
        text = Regex.Replace(text, "<[^>]+>", " ");
        text = Regex.Replace(System.Net.WebUtility.HtmlDecode(text), @"\s+", " ");

        var battery = new BatteryInfo
        {
            BatteryReportPath = htmlPath,
            Manufacturer = Value("Manufacturer", FindText(text, "MANUFACTURER")),
            Chemistry = Value("Chemistry", FindText(text, "CHEMISTRY")),
            DesignCapacityMwh = IntValue("Design capacity", FindNumberAfter(text, "DESIGN CAPACITY")),
            FullChargeCapacityMwh = IntValue("Full charge capacity", FindNumberAfter(text, "FULL CHARGE CAPACITY")),
            CycleCount = IntValue("Cycle count", FindNumberAfter(text, "CYCLE COUNT"))
        };

        if (battery.DesignCapacityMwh.Value is int design && battery.FullChargeCapacityMwh.Value is int full && design > 0)
        {
            var wear = Math.Clamp((1d - full / (double)design) * 100d, 0, 100);
            battery.WearLevelPercent = new(Math.Round(wear, 1), "powercfg batteryreport parser");
            battery.Inferences.Add(wear <= 10 ? "Desgaste bajo: compatible con poco uso o batería reemplazada." : wear >= 30 ? "Desgaste elevado: indica uso móvil considerable o envejecimiento." : "Desgaste moderado.");
        }
        else
        {
            battery.WearLevelPercent = InspectionValue<double>.Missing("powercfg batteryreport parser", "Capacidades no disponibles");
        }

        return battery;
    }

    private static InspectionValue<string> Value(string label, string? value)
        => string.IsNullOrWhiteSpace(value) ? InspectionValue<string>.Missing("powercfg batteryreport parser", $"{label} not found") : new(value, "powercfg batteryreport parser");

    private static InspectionValue<int> IntValue(string label, int? value)
        => value.HasValue ? new(value.Value, "powercfg batteryreport parser") : InspectionValue<int>.Missing("powercfg batteryreport parser", $"{label} not found");

    private static string? FindText(string text, string label)
    {
        var match = Regex.Match(text, $"{Regex.Escape(label)}\\s+([^\\d][A-Z0-9\\-_/ .]+?)(?:\\s+[A-Z ]{{3,}}|$)", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value.Trim() : null;
    }

    private static int? FindNumberAfter(string text, string label)
    {
        var match = Regex.Match(text, $"{Regex.Escape(label)}\\s+([0-9,\\.]+)", RegexOptions.IgnoreCase);
        if (!match.Success) return null;
        var digits = Regex.Replace(match.Groups[1].Value, "[^0-9]", "");
        return int.TryParse(digits, out var value) ? value : null;
    }
}
