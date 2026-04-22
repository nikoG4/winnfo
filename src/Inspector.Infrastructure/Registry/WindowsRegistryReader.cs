using Microsoft.Win32;

namespace Inspector.Infrastructure.Registry;

internal static class WindowsRegistryReader
{
    public static string? ReadString(RegistryHive hive, string subKey, string name)
    {
        using var baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64);
        using var key = baseKey.OpenSubKey(subKey);
        return key?.GetValue(name)?.ToString();
    }

    public static int? ReadInt(RegistryHive hive, string subKey, string name)
    {
        using var baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64);
        using var key = baseKey.OpenSubKey(subKey);
        var value = key?.GetValue(name);
        return value is int i ? i : int.TryParse(value?.ToString(), out var parsed) ? parsed : null;
    }
}
