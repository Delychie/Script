using System.Text;
using System.Text.Json;
using FsocietyInjector.Models;
using FsocietyInjector.Services;

namespace FsocietyInjector;

/// <summary>
/// A Command Prompt DLL injector. It runs in a real console window, so the
/// window chrome, fonts, scrollbar, selection and history are genuine cmd.
///
/// Inject with:
///     C:\Windows\system32>dll inject
///     DLL path: &lt;paste the .dll path&gt;
///     Process path: &lt;paste the target's .exe path&gt;
///
/// The DLL and process paths are remembered between runs and pre-filled the
/// next time (just press Enter to reuse them).
/// </summary>
internal static class Program
{
    private const string Prompt = "C:\\Windows\\system32>";

    private static readonly string CfgPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "fsociety", "injector.json");

    private sealed class Settings { public string? Dll { get; set; } public string? Proc { get; set; } }

    private static Settings _cfg = new();
    private static List<ProcessModel> _procs = new();

    private static void Main()
    {
        // Windows prepends "Administrator: " to an elevated console's title.
        Console.Title = "Command Prompt";
        try { Console.OutputEncoding = Encoding.UTF8; } catch { /* redirected */ }
        LoadCfg();

        Console.WriteLine("Microsoft Windows [Version 10.0.22631.4460]");
        Console.WriteLine("(c) Microsoft Corporation. All rights reserved.");
        Console.WriteLine();

        while (true)
        {
            Console.Write(Prompt);
            var line = Console.ReadLine();   // real console line editing + history
            if (line is null) break;         // Ctrl+Z / EOF
            Execute(line.Trim());
        }
    }

    // ============================ command dispatch ============================

    private static void Execute(string cmd)
    {
        if (cmd.Length == 0) return;

        var parts = cmd.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var verb = parts[0].ToLowerInvariant();
        var arg = parts.Length > 1 ? string.Join(' ', parts[1..]) : string.Empty;

        switch (verb)
        {
            case "dll": case "inject": InjectFlow(verb, arg); break;
            case "help": case "?": Help(); break;
            case "list": case "ls": case "ps": RefreshProcs(); PrintList(); break;
            case "refresh":
                RefreshProcs();
                Tag("[+]", ConsoleColor.Green, $"{_procs.Count} processes.");
                Console.WriteLine();
                break;
            case "cls": case "clear": Console.Clear(); break;
            case "ver":
                Console.WriteLine();
                Console.WriteLine("Microsoft Windows [Version 10.0.22631.4460]");
                Console.WriteLine();
                break;
            case "exit": Environment.Exit(0); break;
            default:
                Console.WriteLine($"'{verb}' is not recognized as an internal or external command,");
                Console.WriteLine("operable program or batch file.");
                Console.WriteLine();
                break;
        }
    }

    private static void Help()
    {
        Console.WriteLine();
        Console.WriteLine("  dll inject           inject a dll (asks for the dll path, then the process path)");
        Console.WriteLine("  list                 enumerate running processes (with paths)");
        Console.WriteLine("  refresh              re-scan processes");
        Console.WriteLine("  cls                  clear the screen");
        Console.WriteLine("  exit                 close");
        Console.WriteLine();
    }

    // ============================ the inject flow ============================

    private static void InjectFlow(string verb, string arg)
    {
        // Accept "dll inject", "dll inject <dllpath>", or bare "inject".
        if (verb == "dll")
        {
            var sub = arg.Split((char[]?)null, 2, StringSplitOptions.RemoveEmptyEntries);
            if (sub.Length == 0 || !sub[0].Equals("inject", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("usage: dll inject");
                Console.WriteLine();
                return;
            }
            arg = sub.Length > 1 ? sub[1] : string.Empty;
        }

        // DLL path — pasted on the same line, or asked for (pre-filled).
        string dll = string.IsNullOrWhiteSpace(arg) ? AskPath("DLL path: ", _cfg.Dll) : arg.Trim().Trim('"');
        if (dll.Length == 0) { Tag("[x]", ConsoleColor.Red, "cancelled."); Console.WriteLine(); return; }
        if (!File.Exists(dll)) { Tag("[x]", ConsoleColor.Red, $"dll not found: {dll}"); Console.WriteLine(); return; }
        _cfg.Dll = dll; SaveCfg();

        // Process path (pre-filled).
        var procPath = AskPath("Process path: ", _cfg.Proc);
        if (procPath.Length == 0) { Tag("[x]", ConsoleColor.Red, "cancelled."); Console.WriteLine(); return; }

        var target = Resolve(procPath);
        if (target is null)
        {
            Tag("[x]", ConsoleColor.Red, $"process not running: {procPath}");
            Console.WriteLine("      (run 'list' to see running processes and their paths.)");
            Console.WriteLine();
            return;
        }
        _cfg.Proc = procPath; SaveCfg();

        Inject(target, dll);
    }

    private static void Inject(ProcessModel target, string dll)
    {
        if (target.ArchLabel == "x86")
        {
            Tag("[x]", ConsoleColor.Red,
                $"{target.Name} is 32-bit; this injector is x64 and can only load into x64.");
            Console.WriteLine();
            return;
        }

        var f = Path.GetFileName(dll);
        WriteDim($"  [*] injecting {f} -> {target.Name} ({target.Id})...");

        var result = InjectionService.Inject(target.Id, dll);

        if (result.Success) Tag("[+]", ConsoleColor.Green, result.Message);
        else                Tag("[x]", ConsoleColor.Red, result.Message);
        Console.WriteLine();
    }

    /// <summary>
    /// Matches a running process from a pasted exe path — by full path first,
    /// then file name, then the raw string as a process name.
    /// </summary>
    private static ProcessModel? Resolve(string path)
    {
        RefreshProcs();
        var file = Path.GetFileName(path);

        return _procs.FirstOrDefault(p =>
                   !string.IsNullOrEmpty(p.Path) &&
                   string.Equals(p.Path, path, StringComparison.OrdinalIgnoreCase))
            ?? _procs.FirstOrDefault(p =>
                   file.Length > 0 &&
                   string.Equals(p.Name, file, StringComparison.OrdinalIgnoreCase))
            ?? _procs.FirstOrDefault(p =>
                   string.Equals(p.Name, path, StringComparison.OrdinalIgnoreCase));
    }

    // ============================ process list ============================

    private static void RefreshProcs() => _procs = ProcessService.Enumerate().ToList();

    private static void PrintList()
    {
        Console.WriteLine();
        WriteDim("   PID     ARCH   PROCESS / PATH");
        WriteDim("   ------  -----  --------------------------------------------");
        foreach (var p in _procs)
        {
            Console.Write($"   {p.Id.ToString().PadRight(6)}  ");
            Console.ForegroundColor = p.ArchLabel == "x86" ? ConsoleColor.Yellow : ConsoleColor.Green;
            Console.Write(p.ArchLabel.PadRight(4));
            Console.ResetColor();
            Console.WriteLine($"   {(string.IsNullOrEmpty(p.Path) ? p.Name : p.Path)}");
        }
        Console.WriteLine();
    }

    // ============================ console helpers ============================

    private static void Tag(string tag, ConsoleColor color, string rest)
    {
        Console.ForegroundColor = color;
        Console.Write("  " + tag + " ");
        Console.ResetColor();
        Console.WriteLine(rest);
    }

    private static void WriteDim(string s)
    {
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.WriteLine(s);
        Console.ResetColor();
    }

    /// <summary>
    /// Reads a line pre-filled with <paramref name="initial"/> that the user
    /// can edit (Backspace) or accept (Enter). Pasting a path streams its
    /// characters in as key events, so paste works normally.
    /// </summary>
    private static string AskPath(string label, string? initial)
    {
        Console.Write(label);
        var sb = new StringBuilder(initial ?? string.Empty);
        Console.Write(sb.ToString());

        while (true)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter) { Console.WriteLine(); return sb.ToString().Trim().Trim('"'); }
            if (key.Key == ConsoleKey.Escape) { ClearLine(sb.Length); return string.Empty; }
            if (key.Key == ConsoleKey.Backspace)
            {
                if (sb.Length > 0) { sb.Length--; Console.Write("\b \b"); }
                continue;
            }
            if (!char.IsControl(key.KeyChar)) { sb.Append(key.KeyChar); Console.Write(key.KeyChar); }
        }
    }

    /// <summary>Wipes the current input back to the label after Esc.</summary>
    private static void ClearLine(int count)
    {
        for (var i = 0; i < count; i++) Console.Write("\b \b");
        Console.WriteLine();
    }

    // ============================ persistence ============================

    private static void LoadCfg()
    {
        try
        {
            if (File.Exists(CfgPath))
                _cfg = JsonSerializer.Deserialize<Settings>(File.ReadAllText(CfgPath)) ?? new Settings();
        }
        catch { _cfg = new Settings(); }
    }

    private static void SaveCfg()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(CfgPath)!);
            File.WriteAllText(CfgPath, JsonSerializer.Serialize(_cfg));
        }
        catch { /* best effort — a read-only profile just means no memory */ }
    }
}
