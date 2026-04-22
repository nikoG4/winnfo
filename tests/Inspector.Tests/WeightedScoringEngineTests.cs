using Inspector.Core.Models;
using Inspector.Core.Scoring;

namespace Inspector.Tests;

public sealed class WeightedScoringEngineTests
{
    [Fact]
    public void Score_ReweightsWhenBatteryIsMissing()
    {
        var report = new InspectionReport
        {
            Battery = null,
            StorageDevices =
            [
                new StorageDeviceInfo
                {
                    Model = "Test SSD",
                    Smart = new SmartInfo
                    {
                        Available = true,
                        Source = "test",
                        PowerOnHours = 90,
                        PowerCycles = 20,
                        HealthPercent = 99,
                        TotalHostWritesGb = 120
                    }
                }
            ],
            UsageHistory = new UsageHistoryInfo { EventsPerDay = 0.1 }
        };

        var result = new WeightedScoringEngine(new ScoringConfiguration()).Score(report);

        Assert.Equal(UsageLevel.VeryLow, result.UsageLevel);
        Assert.True(result.ConditionScore >= 90);
        Assert.DoesNotContain(result.Alerts, a => a.Code == "high_battery_wear");
    }

    [Fact]
    public void Score_DetectsOldMachineWithLowDiskHours()
    {
        var report = new InspectionReport
        {
            Firmware = new FirmwareInfo
            {
                BiosDate = new InspectionValue<DateTimeOffset>(DateTimeOffset.Now.AddYears(-6), "test")
            },
            StorageDevices =
            [
                new StorageDeviceInfo
                {
                    Smart = new SmartInfo { Available = true, Source = "test", PowerOnHours = 80, HealthPercent = 100 }
                }
            ]
        };

        var result = new WeightedScoringEngine(new ScoringConfiguration()).Score(report);

        Assert.Contains(result.Alerts, a => a.Code == "possible_storage_replacement");
    }
}
