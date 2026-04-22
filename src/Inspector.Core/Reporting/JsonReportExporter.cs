using System.Text.Json;
using System.Text.Json.Serialization;
using Inspector.Core.Interfaces;
using Inspector.Core.Models;

namespace Inspector.Core.Reporting;

public sealed class JsonReportExporter : IReportExporter
{
    public string Format => "JSON";

    public async Task ExportAsync(InspectionReport report, string path, CancellationToken cancellationToken = default)
    {
        var options = new JsonSerializerOptions
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };
        await using var stream = File.Create(path);
        await JsonSerializer.SerializeAsync(stream, report, options, cancellationToken).ConfigureAwait(false);
    }
}
