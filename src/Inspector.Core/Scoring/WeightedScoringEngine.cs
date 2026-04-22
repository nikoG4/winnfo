using Inspector.Core.Interfaces;
using Inspector.Core.Models;

namespace Inspector.Core.Scoring;

public sealed class WeightedScoringEngine(ScoringConfiguration configuration) : IScoringEngine
{
    public DiagnosticResult Score(InspectionReport report)
    {
        var usage = new List<ScoreContribution>();
        var condition = new List<ScoreContribution>();
        var alerts = new List<DiagnosticAlert>();

        var bestSmart = report.StorageDevices
            .Select(d => new { Device = d, d.Smart })
            .Where(x => x.Smart.Available)
            .ToList();

        AddUsage(usage, "storage.power_on_hours", bestSmart.Select(x => x.Smart.PowerOnHours).Where(v => v.HasValue).Cast<int>().DefaultIfEmpty().Max(),
            configuration.StoragePowerOnHours, "smartctl/WMI", "Se toma el mayor valor entre discos disponibles.");

        AddUsage(usage, "storage.total_host_writes_gb", bestSmart.Select(x => x.Smart.TotalHostWritesGb).Where(v => v.HasValue).Cast<double>().DefaultIfEmpty().Max(),
            configuration.StorageWritesGb, "smartctl", "Señal fuerte para SSD/NVMe cuando smartctl la expone.");

        var healthValues = bestSmart.Select(x => x.Smart.HealthPercent).Where(v => v.HasValue).Cast<int>().ToList();
        if (healthValues.Count > 0)
        {
            var worstHealth = healthValues.Min();
            condition.Add(new("storage.health_percent", worstHealth, configuration.StorageHealth.Weight,
                NormalizeInverse(worstHealth, configuration.StorageHealth.LowUseValue, configuration.StorageHealth.HighUseValue),
                "smartctl", "Menor salud detectada entre discos."));
        }

        if (report.Battery is not null)
        {
            if (report.Battery.CycleCount.IsAvailable && report.Battery.CycleCount.Value is int cycles)
                AddUsage(usage, "battery.cycle_count", cycles, configuration.BatteryCycles, report.Battery.CycleCount.Source, "Ciclos bajos suelen acompañar poco uso móvil.");

            if (report.Battery.WearLevelPercent.IsAvailable && report.Battery.WearLevelPercent.Value is double wear)
            {
                AddUsage(usage, "battery.wear_percent", wear, configuration.BatteryWear, report.Battery.WearLevelPercent.Source, "Desgaste bajo suma a menor uso.");
                condition.Add(new("battery.wear_percent", wear, configuration.BatteryWear.Weight,
                    Normalize(wear, configuration.BatteryWear.LowUseValue, configuration.BatteryWear.HighUseValue),
                    report.Battery.WearLevelPercent.Source, "Desgaste calculado contra capacidad de diseño."));
            }
        }

        if (report.UsageHistory.EventsPerDay > 0)
            AddUsage(usage, "system.events_per_day", report.UsageHistory.EventsPerDay, configuration.SystemEventFrequency,
                report.UsageHistory.Source, "Frecuencia de arranques, apagados, suspensión y reanudación.");

        if (report.OperatingSystem.InstallDate.IsAvailable && report.OperatingSystem.InstallDate.Value is DateTimeOffset installDate)
        {
            var ageDays = Math.Max(0, (DateTimeOffset.Now - installDate).TotalDays);
            AddUsage(usage, "windows.install_age_days", ageDays, configuration.WindowsInstallAge,
                report.OperatingSystem.InstallDate.Source, "Señal débil: reinstalar Windows puede resetearla.");
        }

        DetectInconsistencies(report, alerts);
        AddConditionFromEvents(report, condition);

        var usageScore = WeightedAverage(usage);
        var conditionRisk = WeightedConditionRisk(condition, report);
        var conditionScore = condition.Count == 0 ? 78 : 100 - conditionRisk;
        conditionScore = Math.Clamp(conditionScore, 0, 100);

        var availableSignals = usage.Count + condition.Count;
        var expectedSignals = report.Battery is null ? 6 : 8;
        var confidenceScore = Math.Clamp(availableSignals / (double)expectedSignals - report.Issues.Count(i => i.Severity == IssueSeverity.Error) * configuration.MissingSignalConfidencePenalty, 0, 1);

        return new DiagnosticResult
        {
            UsageScore = Math.Round(usageScore, 1),
            ConditionScore = Math.Round(conditionScore, 1),
            UsageLevel = ToUsageLevel(usageScore),
            ConditionLevel = ToConditionLevel(conditionScore),
            Confidence = confidenceScore >= 0.72 ? ConfidenceLevel.High : confidenceScore >= 0.42 ? ConfidenceLevel.Medium : ConfidenceLevel.Low,
            UsageContributions = usage,
            ConditionContributions = condition,
            Alerts = alerts,
            Summary = BuildSummary(usageScore, conditionScore, alerts)
        };
    }

    private static void AddUsage(List<ScoreContribution> list, string signal, double value, SignalWeight weight, string source, string note)
    {
        if (value <= 0) return;
        list.Add(new(signal, Math.Round(value, 2), weight.Weight, Normalize(value, weight.LowUseValue, weight.HighUseValue), source, note));
    }

    private static double WeightedAverage(List<ScoreContribution> values)
    {
        if (values.Count == 0) return 0;
        var totalWeight = values.Sum(v => v.Weight);
        return totalWeight <= 0 ? 0 : values.Sum(v => v.NormalizedScore * v.Weight) / totalWeight;
    }

    private double WeightedConditionRisk(List<ScoreContribution> values, InspectionReport report)
    {
        if (values.Count == 0) return 22;
        var expectedWeight = 0.08;
        if (report.StorageDevices.Count > 0) expectedWeight += configuration.StorageHealth.Weight;
        if (report.Battery is not null) expectedWeight += configuration.BatteryWear.Weight;
        expectedWeight = Math.Max(expectedWeight, values.Sum(v => v.Weight));
        return values.Sum(v => v.NormalizedScore * v.Weight) / expectedWeight;
    }

    private static double Normalize(double value, double low, double high)
    {
        if (Math.Abs(high - low) < double.Epsilon) return 50;
        return Math.Clamp((value - low) / (high - low), 0, 1) * 100;
    }

    private static double NormalizeInverse(double value, double good, double bad)
    {
        if (Math.Abs(good - bad) < double.Epsilon) return 50;
        return Math.Clamp((good - value) / (good - bad), 0, 1) * 100;
    }

    private static void DetectInconsistencies(InspectionReport report, List<DiagnosticAlert> alerts)
    {
        var biosAgeYears = report.Firmware.BiosDate.Value is DateTimeOffset biosDate
            ? (DateTimeOffset.Now - biosDate).TotalDays / 365.25
            : 0;
        var maxDiskHours = report.StorageDevices.Select(d => d.Smart.PowerOnHours ?? 0).DefaultIfEmpty().Max();

        if (biosAgeYears >= 4 && maxDiskHours is > 0 and < 300)
            alerts.Add(new("possible_storage_replacement", "El firmware sugiere un equipo antiguo, pero el disco reporta muy pocas horas. Posible reemplazo de SSD/HDD.", IssueSeverity.Warning));

        if (report.StorageDevices.Any(d => d.Smart.HealthPercent is <= 75))
            alerts.Add(new("low_storage_health", "Al menos un disco reporta salud SMART baja.", IssueSeverity.Error));

        if (report.Battery?.WearLevelPercent.Value is >= 35)
            alerts.Add(new("high_battery_wear", "La batería muestra desgaste elevado.", IssueSeverity.Warning));

        if (report.UsageHistory.UnexpectedShutdowns >= 8)
            alerts.Add(new("unexpected_shutdowns", "Hay varios apagados inesperados registrados.", IssueSeverity.Warning));
    }

    private static void AddConditionFromEvents(InspectionReport report, List<ScoreContribution> condition)
    {
        if (report.UsageHistory.UnexpectedShutdowns > 0)
        {
            var score = Math.Clamp(report.UsageHistory.UnexpectedShutdowns * 7, 0, 100);
            condition.Add(new("events.unexpected_shutdowns", report.UsageHistory.UnexpectedShutdowns, 0.08, score, report.UsageHistory.Source, "Apagados inesperados elevan riesgo operativo."));
        }
    }

    private static UsageLevel ToUsageLevel(double score) => score switch
    {
        < 18 => UsageLevel.VeryLow,
        < 38 => UsageLevel.Low,
        < 62 => UsageLevel.Medium,
        < 82 => UsageLevel.High,
        _ => UsageLevel.Intensive
    };

    private static ConditionLevel ToConditionLevel(double score) => score switch
    {
        >= 90 => ConditionLevel.Excellent,
        >= 80 => ConditionLevel.VeryGood,
        >= 68 => ConditionLevel.Good,
        >= 50 => ConditionLevel.Regular,
        _ => ConditionLevel.Risky
    };

    private static string BuildSummary(double usage, double condition, List<DiagnosticAlert> alerts)
    {
        var risk = alerts.Any(a => a.Severity == IssueSeverity.Error) ? " Hay alertas críticas que conviene revisar." : "";
        return $"Uso estimado {ToUsageLevel(usage)} con estado general {ToConditionLevel(condition)}.{risk}";
    }
}
