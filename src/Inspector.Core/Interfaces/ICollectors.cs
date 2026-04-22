using Inspector.Core.Models;

namespace Inspector.Core.Interfaces;

public interface IInspectorCollector
{
    string Name { get; }
    Task CollectAsync(InspectionReport report, CancellationToken cancellationToken);
}

public interface IInspectionOrchestrator
{
    Task<InspectionReport> RunAsync(CancellationToken cancellationToken = default);
}

public interface IScoringEngine
{
    DiagnosticResult Score(InspectionReport report);
}

public interface IReportExporter
{
    string Format { get; }
    Task ExportAsync(InspectionReport report, string path, CancellationToken cancellationToken = default);
}
