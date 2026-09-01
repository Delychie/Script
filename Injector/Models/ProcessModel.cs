namespace FsocietyInjector.Models;

/// <summary>
/// One row in the process list. Immutable snapshot taken at scan time.
/// <paramref name="Path"/> is the full executable path (empty when it can't be
/// read — e.g. a protected process, or a 32-bit target seen from x64).
/// </summary>
public sealed record ProcessModel(
    int Id,
    string Name,
    string Path,
    bool Is64Bit,
    string ArchLabel)
{
    /// <summary>Text shown in the list, e.g. "RobloxPlayerBeta.exe  ·  12345".</summary>
    public string Display => $"{Name}  ·  {Id}";
}
