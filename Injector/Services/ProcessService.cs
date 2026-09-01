using System.Diagnostics;
using MrrpInjector.Models;
using MrrpInjector.Native;

namespace MrrpInjector.Services;

/// <summary>
/// Enumerates running processes and reports their bitness so the UI can warn
/// about x86/x64 mismatches before an inject is ever attempted.
/// </summary>
public static class ProcessService
{
    /// <summary>
    /// Returns the visible, injectable processes, sorted with likely targets
    /// (anything named "roblox…") floated to the top.
    /// </summary>
    public static IReadOnlyList<ProcessModel> Enumerate()
    {
        var results = new List<ProcessModel>();

        foreach (var proc in Process.GetProcesses())
        {
            try
            {
                // System / idle processes have id 0 or throw on access; skip them.
                if (proc.Id <= 0)
                    continue;

                var is64 = TryIs64Bit(proc, out var known);
                var arch = !known ? "—" : is64 ? "x64" : "x86";

                string title;
                try { title = proc.MainWindowTitle ?? string.Empty; }
                catch { title = string.Empty; }

                results.Add(new ProcessModel(
                    Id: proc.Id,
                    Name: SafeName(proc),
                    Title: title,
                    Is64Bit: is64,
                    ArchLabel: arch));
            }
            catch
            {
                // Protected / exited process — nothing we can do with it, drop it.
            }
            finally
            {
                proc.Dispose();
            }
        }

        return results
            .GroupBy(p => p.Id).Select(g => g.First()) // de-dupe defensively
            .OrderByDescending(p => p.Name.StartsWith("roblox", StringComparison.OrdinalIgnoreCase))
            .ThenBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static string SafeName(Process p)
    {
        try { return p.ProcessName + ".exe"; }
        catch { return "(unknown)"; }
    }

    /// <summary>
    /// Determines whether the target runs as 64-bit. On a 64-bit OS a process
    /// is 32-bit only if it is running under WOW64.
    /// </summary>
    private static bool TryIs64Bit(Process proc, out bool known)
    {
        known = false;
        if (!Environment.Is64BitOperatingSystem)
        {
            known = true;
            return false; // 32-bit OS: everything is x86.
        }

        try
        {
            if (NativeMethods.IsWow64Process(proc.Handle, out var isWow64))
            {
                known = true;
                return !isWow64; // under WOW64 => the process itself is 32-bit.
            }
        }
        catch
        {
            // Access denied on a protected process; leave bitness unknown.
        }

        return false;
    }
}
