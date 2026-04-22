using System.Globalization;
using System.Windows;

namespace Inspector.App.Localization;

internal static class LocalizationService
{
    public static void Apply()
    {
        var culture = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("es", StringComparison.OrdinalIgnoreCase)
            ? "es"
            : "en";

        var dictionary = new ResourceDictionary
        {
            Source = new Uri($"/Resources/Strings.{culture}.xaml", UriKind.Relative)
        };

        Application.Current.Resources.MergedDictionaries.Add(dictionary);
    }
}
