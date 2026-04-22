using Inspector.Core.Interfaces;
using Inspector.Core.Models;

namespace Inspector.Core.Services;

public sealed class InspectionOrchestrator(IEnumerable<IInspectorCollector> collectors, IScoringEngine scoringEngine) : IInspectionOrchestrator
{
    public async Task<InspectionReport> RunAsync(CancellationToken cancellationToken = default)
    {
        var report = new InspectionReport();

        foreach (var collector in collectors)
        {
            try
            {
                await collector.CollectAsync(report, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                report.Issues.Add(new(collector.Name, "Collector failed", ex.Message, IssueSeverity.Error));
            }
        }

        report.Diagnostic = scoringEngine.Score(report);
        return report;
    }
}
