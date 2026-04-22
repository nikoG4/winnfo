using System.Windows;
using Inspector.App.Localization;
using Inspector.App.ViewModels;
using Inspector.Core.Interfaces;
using Inspector.Core.Reporting;
using Inspector.Core.Scoring;
using Inspector.Core.Services;
using Inspector.Infrastructure;
using Microsoft.Extensions.DependencyInjection;

namespace Inspector.App;

public partial class App : Application
{
    private ServiceProvider? _services;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        LocalizationService.Apply();
        var services = new ServiceCollection();
        services.AddSingleton(ScoringConfigurationLoader.Load());
        services.AddSingleton<IScoringEngine, WeightedScoringEngine>();
        services.AddSingleton<IInspectionOrchestrator, InspectionOrchestrator>();
        services.AddSingleton<IReportExporter, JsonReportExporter>();
        services.AddSingleton<IReportExporter, HtmlReportExporter>();
        services.AddInspectorInfrastructure();
        services.AddSingleton<MainViewModel>();
        services.AddSingleton<MainWindow>();

        _services = services.BuildServiceProvider();
        _services.GetRequiredService<MainWindow>().Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _services?.Dispose();
        base.OnExit(e);
    }
}
