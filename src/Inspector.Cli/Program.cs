using Inspector.Core.Interfaces;
using Inspector.Core.Reporting;
using Inspector.Core.Scoring;
using Inspector.Core.Services;
using Inspector.Infrastructure;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection();
services.AddSingleton(new ScoringConfiguration());
services.AddSingleton<IScoringEngine, WeightedScoringEngine>();
services.AddSingleton<IInspectionOrchestrator, InspectionOrchestrator>();
services.AddSingleton<IReportExporter, JsonReportExporter>();
services.AddSingleton<IReportExporter, HtmlReportExporter>();
services.AddInspectorInfrastructure();

await using var provider = services.BuildServiceProvider();
var orchestrator = provider.GetRequiredService<IInspectionOrchestrator>();
var report = await orchestrator.RunAsync();

Console.WriteLine("Windows Hardware Usage Inspector - CLI diagnostic");
Console.WriteLine($"{report.Identity.Manufacturer.Value} {report.Identity.Model.Value} ({report.Identity.DeviceType.Value})");
Console.WriteLine($"Usage: {report.Diagnostic.UsageScore:0.0} {report.Diagnostic.UsageLevel} | Condition: {report.Diagnostic.ConditionScore:0.0} {report.Diagnostic.ConditionLevel} | Confidence: {report.Diagnostic.Confidence}");
Console.WriteLine();
Console.WriteLine("Storage:");
foreach (var disk in report.StorageDevices)
{
    Console.WriteLine($"- {disk.Model}");
    Console.WriteLine($"  Serial: {disk.SerialNumber}");
    Console.WriteLine($"  Bus/Media: {disk.BusType}/{disk.MediaType}");
    Console.WriteLine($"  Drives: {(disk.DriveLetters.Count == 0 ? "N/D" : string.Join(", ", disk.DriveLetters))}");
    Console.WriteLine($"  SMART source: {disk.Smart.Source}");
    Console.WriteLine($"  PowerOnHours: {disk.Smart.PowerOnHours?.ToString() ?? "N/D"}");
    Console.WriteLine($"  PowerCycles: {disk.Smart.PowerCycles?.ToString() ?? "N/D"}");
    Console.WriteLine($"  Health: {disk.Smart.HealthPercent?.ToString() ?? "N/D"}");
    Console.WriteLine($"  Temperature: {disk.Smart.TemperatureCelsius?.ToString("0.#") ?? "N/D"}");
    Console.WriteLine($"  Writes GB: {disk.Smart.TotalHostWritesGb?.ToString("0.##") ?? "N/D"}");
    if (!string.IsNullOrWhiteSpace(disk.Smart.Error))
        Console.WriteLine($"  Note: {disk.Smart.Error}");
}

Console.WriteLine();
Console.WriteLine("Issues:");
if (report.Issues.Count == 0)
{
    Console.WriteLine("- none");
}
else
{
    foreach (var issue in report.Issues)
        Console.WriteLine($"- {issue.Severity} [{issue.Source}] {issue.Message}: {issue.Detail}");
}

var outputPath = args.FirstOrDefault(a => a.EndsWith(".json", StringComparison.OrdinalIgnoreCase));
if (!string.IsNullOrWhiteSpace(outputPath))
{
    var exporter = provider.GetServices<IReportExporter>().First(e => e.Format == "JSON");
    await exporter.ExportAsync(report, outputPath);
    Console.WriteLine();
    Console.WriteLine($"JSON exported: {outputPath}");
}
