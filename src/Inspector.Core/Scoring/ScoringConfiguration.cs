namespace Inspector.Core.Scoring;

public sealed class ScoringConfiguration
{
    public SignalWeight StoragePowerOnHours { get; set; } = new(0.24, 150, 4500, "Horas de uso del disco");
    public SignalWeight StorageWritesGb { get; set; } = new(0.18, 250, 25000, "Escritura acumulada en SSD/NVMe");
    public SignalWeight StorageHealth { get; set; } = new(0.22, 98, 70, "Salud SMART del disco");
    public SignalWeight BatteryCycles { get; set; } = new(0.16, 40, 650, "Ciclos de batería");
    public SignalWeight BatteryWear { get; set; } = new(0.14, 5, 35, "Desgaste de batería");
    public SignalWeight SystemEventFrequency { get; set; } = new(0.08, 0.15, 2.2, "Frecuencia histórica de eventos");
    public SignalWeight WindowsInstallAge { get; set; } = new(0.04, 30, 1500, "Antigüedad de instalación de Windows");
    public double MissingSignalConfidencePenalty { get; set; } = 0.09;
}

public sealed record SignalWeight(double Weight, double LowUseValue, double HighUseValue, string Description);
