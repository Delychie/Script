namespace MrrpInjector.Models;

/// <summary>
/// One row in the process picker. Immutable snapshot taken at scan time.
/// </summary>
public sealed record ProcessModel(
    int Id,
    string Name,
    string Title,
    bool Is64Bit,
    string ArchLabel)
{
    /// <summary>Text shown in the list, e.g. "RobloxPlayerBeta.exe  ·  12345".</summary>
    public string Display => $"{Name}  ·  {Id}";
}
