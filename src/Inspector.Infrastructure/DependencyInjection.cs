using Inspector.Core.Interfaces;
using Inspector.Infrastructure.Collectors;
using Inspector.Infrastructure.ExternalTools;
using Inspector.Infrastructure.Native;
using Inspector.Infrastructure.Sensors;
using Microsoft.Extensions.DependencyInjection;

namespace Inspector.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInspectorInfrastructure(this IServiceCollection services)
    {
        services.AddSingleton<SmartctlService>();
        services.AddSingleton<WindowsStorageService>();
        services.AddSingleton<HardwareSensorReader>();
        services.AddSingleton<IInspectorCollector, IdentityFirmwareOsCollector>();
        services.AddSingleton<IInspectorCollector, HardwareCollector>();
        services.AddSingleton<IInspectorCollector, StorageCollector>();
        services.AddSingleton<IInspectorCollector, BatteryCollector>();
        services.AddSingleton<IInspectorCollector, UsageHistoryCollector>();
        services.AddSingleton<IInspectorCollector, NetworkDeviceCollector>();
        return services;
    }
}
