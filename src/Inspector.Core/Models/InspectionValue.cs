namespace Inspector.Core.Models;

public sealed record InspectionValue<T>(
    T? Value,
    string Source,
    bool IsAvailable = true,
    string? Note = null)
{
    public static InspectionValue<T> Missing(string source, string reason) => new(default, source, false, reason);
}

public sealed record CollectionIssue(string Source, string Message, string? Detail = null, IssueSeverity Severity = IssueSeverity.Warning);

public enum IssueSeverity
{
    Info,
    Warning,
    Error
}

public sealed record DiagnosticAlert(string Code, string Message, IssueSeverity Severity);

public enum UsageLevel
{
    VeryLow,
    Low,
    Medium,
    High,
    Intensive
}

public enum ConditionLevel
{
    Excellent,
    VeryGood,
    Good,
    Regular,
    Risky
}

public enum ConfidenceLevel
{
    Low,
    Medium,
    High
}
