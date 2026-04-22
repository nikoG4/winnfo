using Inspector.Core.Models;
using LibreHardwareMonitor.Hardware;

namespace Inspector.Infrastructure.Sensors;

public sealed class HardwareSensorReader
{
    public SensorSnapshot Read()
    {
        var snapshot = new SensorSnapshot();
        try
        {
            var computer = new Computer
            {
                IsCpuEnabled = true,
                IsGpuEnabled = true
            };
            try
            {
                computer.Open();
                foreach (var hardware in computer.Hardware)
                {
                    hardware.Update();
                    foreach (var subHardware in hardware.SubHardware)
                        subHardware.Update();

                    var sensors = hardware.Sensors.Concat(hardware.SubHardware.SelectMany(h => h.Sensors)).ToList();
                    if (hardware.HardwareType == HardwareType.Cpu)
                    {
                        snapshot.CpuTemperatureCelsius = sensors
                            .Where(s => s.SensorType == SensorType.Temperature && s.Value.HasValue)
                            .Select(s => (double)s.Value!.Value)
                            .DefaultIfEmpty()
                            .Max();
                        snapshot.CpuLoadPercent = sensors
                            .Where(s => s.SensorType == SensorType.Load && s.Value.HasValue && s.Name.Contains("Total", StringComparison.OrdinalIgnoreCase))
                            .Select(s => (double)s.Value!.Value)
                            .DefaultIfEmpty()
                            .Max();
                    }
                    else if (hardware.HardwareType is HardwareType.GpuAmd or HardwareType.GpuNvidia or HardwareType.GpuIntel)
                    {
                        snapshot.GpuSensors.Add(new GpuSensorSnapshot(
                            hardware.Name,
                            sensors.Where(s => s.SensorType == SensorType.Temperature && s.Value.HasValue).Select(s => (double?)s.Value!.Value).FirstOrDefault(),
                            sensors.Where(s => s.SensorType == SensorType.Load && s.Value.HasValue).Select(s => (double?)s.Value!.Value).FirstOrDefault()));
                    }
                }
            }
            finally
            {
                computer.Close();
            }
        }
        catch (Exception ex)
        {
            snapshot.Error = ex.Message;
        }
        return snapshot;
    }
}

public sealed class SensorSnapshot
{
    public double? CpuTemperatureCelsius { get; set; }
    public double? CpuLoadPercent { get; set; }
    public List<GpuSensorSnapshot> GpuSensors { get; set; } = [];
    public string? Error { get; set; }
}

public sealed record GpuSensorSnapshot(string Name, double? TemperatureCelsius, double? LoadPercent);
