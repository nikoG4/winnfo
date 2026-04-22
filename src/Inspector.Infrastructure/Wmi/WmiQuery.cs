using System.Management;

namespace Inspector.Infrastructure.Wmi;

internal static class WmiQuery
{
    public static List<Dictionary<string, object?>> Query(string query, string scope = @"root\CIMV2")
    {
        var result = new List<Dictionary<string, object?>>();
        using var searcher = new ManagementObjectSearcher(scope, query);
        using var collection = searcher.Get();
        foreach (ManagementObject item in collection)
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            foreach (PropertyData property in item.Properties)
                row[property.Name] = property.Value;
            result.Add(row);
        }
        return result;
    }

    public static Dictionary<string, object?> FirstOrEmpty(string query, string scope = @"root\CIMV2")
        => Query(query, scope).FirstOrDefault() ?? new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);

    public static string? String(this IReadOnlyDictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var value) ? value?.ToString()?.Trim() : null;

    public static int? Int(this IReadOnlyDictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var value) && int.TryParse(value?.ToString(), out var parsed) ? parsed : null;

    public static uint? UInt(this IReadOnlyDictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var value) && uint.TryParse(value?.ToString(), out var parsed) ? parsed : null;

    public static ulong? ULong(this IReadOnlyDictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var value) && ulong.TryParse(value?.ToString(), out var parsed) ? parsed : null;

    public static bool? Bool(this IReadOnlyDictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var value) && bool.TryParse(value?.ToString(), out var parsed) ? parsed : null;

    public static DateTimeOffset? WmiDate(this IReadOnlyDictionary<string, object?> row, string key)
    {
        var text = row.String(key);
        if (string.IsNullOrWhiteSpace(text)) return null;
        try { return new DateTimeOffset(ManagementDateTimeConverter.ToDateTime(text)); }
        catch { return null; }
    }
}
