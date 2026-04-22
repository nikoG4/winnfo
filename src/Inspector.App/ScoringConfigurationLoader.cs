using System.IO;
using System.Text.Json;
using Inspector.Core.Scoring;

namespace Inspector.App;

internal static class ScoringConfigurationLoader
{
    public static ScoringConfiguration Load()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", "scoring-settings.json");
        if (!File.Exists(path))
            return new ScoringConfiguration();

        try
        {
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            return JsonSerializer.Deserialize<ScoringConfiguration>(File.ReadAllText(path), options) ?? new ScoringConfiguration();
        }
        catch
        {
            return new ScoringConfiguration();
        }
    }
}
