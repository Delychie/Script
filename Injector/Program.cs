using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using FsocietyInjector.Models;
using FsocietyInjector.Services;

namespace FsocietyInjector;

/// <summary>
/// A Command Prompt DLL injector. It runs in a real console window, so the
/// window chrome, fonts, scrollbar, selection and history are genuine cmd.
///
/// Besides the injector's own <c>dll inject</c> verb it implements the real
/// cmd built-ins people reach for out of habit — <c>color 0a</c>, <c>cls</c>,
/// <c>title</c>, <c>echo</c>, <c>cd</c>/<c>dir</c>, <c>date</c>/<c>time</c>,
/// <c>prompt</c>, <c>set</c>, <c>pause</c>, <c>ver</c>, <c>whoami</c>,
/// <c>hostname</c> — so it behaves like the shell it looks like.
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
    private static readonly string CfgPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "fsociety", "injector.json");

    private sealed class Settings { public string? Dll { get; set; } public string? Proc { get; set; } }

    private static Settings _cfg = new();
    private static List<ProcessModel> _procs = new();

    // cmd shell state.
    private static string _cwd = Environment.SystemDirectory;   // C:\Windows\system32
    private static string _promptTemplate = "$P$G";             // cmd default
    private static bool _echoOn = true;
    private static ConsoleColor _fg;
    private static ConsoleColor _bg;

    // The real Windows version of this machine, as cmd would print it.
    private static readonly string WinVer = DetectWinVer();

    private static void Main()
    {
        // Windows prepends "Administrator: " to an elevated console's title.
        Console.Title = "Command Prompt";
        try { Console.OutputEncoding = Encoding.UTF8; } catch { /* redirected */ }
        _fg = Console.ForegroundColor;
        _bg = Console.BackgroundColor;
        if (string.IsNullOrEmpty(_cwd) || !Directory.Exists(_cwd)) _cwd = Directory.GetCurrentDirectory();
        LoadCfg();

        Console.WriteLine($"Microsoft Windows [Version {WinVer}]");
        Console.WriteLine("(c) Microsoft Corporation. All rights reserved.");
        Console.WriteLine();

        while (true)
        {
            Console.Write(BuildPrompt());
            var line = Console.ReadLine();   // real console line editing + history
            if (line is null) break;         // Ctrl+Z / EOF
            Execute(line);
        }
    }

    // ============================ command dispatch ============================

    private static void Execute(string raw)
    {
        var cmd = raw.Trim();
        if (cmd.Length == 0) return;

        var parts = cmd.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var verb = parts[0].ToLowerInvariant();
        var arg = parts.Length > 1 ? string.Join(' ', parts[1..]) : string.Empty;

        switch (verb)
        {
            // ----- the injector -----
            case "dll": case "inject": InjectFlow(verb, arg); break;
            case "list": case "ls": case "ps": RefreshProcs(); PrintList(); break;
            case "refresh":
                RefreshProcs();
                Tag("[+]", ConsoleColor.Green, $"{_procs.Count} processes.");
                Console.WriteLine();
                break;

            // ----- real cmd built-ins -----
            case "color":   Color(arg); break;
            case "cls":     Console.Clear(); break;
            case "title":   Console.Title = arg; break;
            case "echo":    Echo(cmd); break;
            case "cd": case "chdir": Chdir(arg); break;
            case "dir":     Dir(arg); break;
            case "prompt":  _promptTemplate = arg.Length == 0 ? "$P$G" : arg; break;
            case "set":     Set(arg); break;
            case "pause":   Pause(); break;
            case "date":    DateCmd(arg); break;
            case "time":    TimeCmd(arg); break;
            case "whoami":  Console.WriteLine($"{Environment.UserDomainName.ToLowerInvariant()}\\{Environment.UserName.ToLowerInvariant()}"); break;
            case "hostname": Console.WriteLine(Environment.MachineName); break;
            case "ver":
                Console.WriteLine();
                Console.WriteLine($"Microsoft Windows [Version {WinVer}]");
                Console.WriteLine();
                break;
            case "help": case "?": Help(); break;
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
        Console.WriteLine();
        Console.WriteLine("  color                 set screen colors, e.g. COLOR 0A");
        Console.WriteLine("  cls                   clear the screen");
        Console.WriteLine("  title                 set the window title");
        Console.WriteLine("  echo                  display a message");
        Console.WriteLine("  cd / dir              change / list the current directory");
        Console.WriteLine("  prompt                change the command prompt");
        Console.WriteLine("  set                   display environment variables");
        Console.WriteLine("  date / time           show the date / time");
        Console.WriteLine("  ver / whoami / hostname / pause");
        Console.WriteLine("  exit                  close");
        Console.WriteLine();
    }

    // ============================ cmd built-ins ============================

    /// <summary>
    /// The real COLOR command: two hex nibbles, background then foreground,
    /// from cmd's 16-colour table. <c>COLOR</c> with no argument restores the
    /// startup colours. The <see cref="ConsoleColor"/> enum order matches
    /// cmd's table exactly, so <c>0A</c> is Black-on-Light-Green.
    /// </summary>
    private static void Color(string arg)
    {
        arg = arg.Trim();

        if (arg.Length == 0)
        {
            _bg = ConsoleColor.Black;
            _fg = Console.ForegroundColor = ConsoleColor.Gray;   // cmd's default 07
            Console.BackgroundColor = _bg;
            Console.Clear();
            return;
        }

        if (arg.Length != 2 ||
            !TryHexNibble(arg[0], out int bg) || !TryHexNibble(arg[1], out int fg))
        {
            // cmd prints its help text on a malformed argument.
            Console.WriteLine("Sets the default console foreground and background colors.");
            Console.WriteLine();
            Console.WriteLine("COLOR [attr]");
            Console.WriteLine();
            Console.WriteLine("  attr        Specifies color attribute of console output");
            Console.WriteLine();
            Console.WriteLine("Color attributes are specified by TWO hex digits -- the first");
            Console.WriteLine("corresponds to the background; the second the foreground.  Each digit");
            Console.WriteLine("can be any of the following values:");
            Console.WriteLine();
            Console.WriteLine("    0 = Black       8 = Gray");
            Console.WriteLine("    1 = Blue        9 = Light Blue");
            Console.WriteLine("    2 = Green       A = Light Green");
            Console.WriteLine("    3 = Aqua        B = Light Aqua");
            Console.WriteLine("    4 = Red         C = Light Red");
            Console.WriteLine("    5 = Purple      D = Light Purple");
            Console.WriteLine("    6 = Yellow      E = Light Yellow");
            Console.WriteLine("    7 = White       F = Bright White");
            Console.WriteLine();
            return;
        }

        if (bg == fg)
        {
            // cmd refuses same fg/bg and sets ERRORLEVEL 1; it prints nothing.
            return;
        }

        _bg = (ConsoleColor)bg;
        _fg = (ConsoleColor)fg;
        Console.BackgroundColor = _bg;
        Console.ForegroundColor = _fg;
        Console.Clear();   // repaint the window in the new colours, like cmd
    }

    private static bool TryHexNibble(char c, out int value)
    {
        c = char.ToUpperInvariant(c);
        if (c >= '0' && c <= '9') { value = c - '0'; return true; }
        if (c >= 'A' && c <= 'F') { value = c - 'A' + 10; return true; }
        value = 0;
        return false;
    }

    private static void Echo(string cmd)
    {
        // Preserve the original spacing/casing after the verb.
        var rest = cmd.Length > 4 ? cmd[4..] : string.Empty;   // strip "echo"

        if (rest.Length == 0)
        {
            Console.WriteLine($"ECHO is {(_echoOn ? "on" : "off")}.");
            return;
        }
        if (rest[0] == '.') { Console.WriteLine(rest[1..]); return; }   // "echo." -> blank line
        if (rest[0] == ' ') rest = rest[1..];

        if (rest.Equals("on", StringComparison.OrdinalIgnoreCase)) { _echoOn = true; return; }
        if (rest.Equals("off", StringComparison.OrdinalIgnoreCase)) { _echoOn = false; return; }

        Console.WriteLine(rest);
    }

    private static void Chdir(string arg)
    {
        arg = arg.Trim();

        if (arg.Length == 0) { Console.WriteLine(_cwd); return; }

        // cmd's "cd /d" also changes drive; we accept and ignore the flag.
        if (arg.StartsWith("/d", StringComparison.OrdinalIgnoreCase))
            arg = arg[2..].Trim();

        arg = arg.Trim('"');
        if (arg.Length == 0) { Console.WriteLine(_cwd); return; }

        string target;
        try { target = Path.GetFullPath(Path.IsPathRooted(arg) ? arg : Path.Combine(_cwd, arg)); }
        catch { Console.WriteLine("The system cannot find the path specified."); return; }

        if (Directory.Exists(target)) _cwd = target.TrimEnd('\\');
        else Console.WriteLine("The system cannot find the path specified.");
    }

    private static void Dir(string arg)
    {
        var path = arg.Trim().Trim('"');
        var dir = path.Length == 0 ? _cwd : (Path.IsPathRooted(path) ? path : Path.Combine(_cwd, path));

        if (!Directory.Exists(dir))
        {
            Console.WriteLine(" Volume in drive C has no label.");
            Console.WriteLine();
            Console.WriteLine("File Not Found");
            Console.WriteLine();
            return;
        }

        DirectoryInfo di;
        FileSystemInfo[] entries;
        try { di = new DirectoryInfo(dir); entries = di.GetFileSystemInfos(); }
        catch (Exception ex) { Console.WriteLine(ex.Message); return; }

        Console.WriteLine(" Volume in drive C has no label.");
        Console.WriteLine(" Volume Serial Number is 0000-0000");
        Console.WriteLine();
        Console.WriteLine($" Directory of {di.FullName}");
        Console.WriteLine();

        long fileCount = 0, dirCount = 0, totalBytes = 0;

        if (di.Parent != null)
        {
            Console.WriteLine($"{di.CreationTime,-22:MM/dd/yyyy  hh:mm tt}    <DIR>          .");
            Console.WriteLine($"{di.CreationTime,-22:MM/dd/yyyy  hh:mm tt}    <DIR>          ..");
            dirCount += 2;
        }

        foreach (var e in entries.OrderBy(e => (e.Attributes & FileAttributes.Directory) == 0)
                                  .ThenBy(e => e.Name, StringComparer.OrdinalIgnoreCase))
        {
            if ((e.Attributes & FileAttributes.Directory) != 0)
            {
                Console.WriteLine($"{e.LastWriteTime:MM/dd/yyyy  hh:mm tt}    <DIR>          {e.Name}");
                dirCount++;
            }
            else
            {
                var len = (e as FileInfo)?.Length ?? 0;
                totalBytes += len;
                fileCount++;
                Console.WriteLine($"{e.LastWriteTime:MM/dd/yyyy  hh:mm tt}    {len,14:n0} {e.Name}");
            }
        }

        Console.WriteLine($"{fileCount,16} File(s) {totalBytes,15:n0} bytes");
        Console.WriteLine($"{dirCount,16} Dir(s)");
        Console.WriteLine();
    }

    private static void Set(string arg)
    {
        arg = arg.Trim();

        // "set NAME=VALUE" assigns; "set NAME" filters; bare "set" lists all.
        var eq = arg.IndexOf('=');
        if (eq > 0)
        {
            var name = arg[..eq].Trim();
            var value = arg[(eq + 1)..];
            if (value.Length == 0) Environment.SetEnvironmentVariable(name, null);
            else Environment.SetEnvironmentVariable(name, value);
            return;
        }

        var vars = Environment.GetEnvironmentVariables()
            .Cast<System.Collections.DictionaryEntry>()
            .Select(e => new { Name = (string)e.Key, Value = (string?)e.Value })
            .Where(e => arg.Length == 0 || e.Name.StartsWith(arg, StringComparison.OrdinalIgnoreCase))
            .OrderBy(e => e.Name, StringComparer.OrdinalIgnoreCase);

        var any = false;
        foreach (var v in vars) { Console.WriteLine($"{v.Name}={v.Value}"); any = true; }
        if (!any && arg.Length > 0)
            Console.WriteLine($"Environment variable {arg} not defined");
    }

    private static void Pause()
    {
        Console.Write("Press any key to continue . . . ");
        Console.ReadKey(intercept: true);
        Console.WriteLine();
    }

    private static void DateCmd(string arg)
    {
        if (arg.Trim().Equals("/t", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine($"{DateTime.Now:ddd MM/dd/yyyy}");
            return;
        }
        Console.WriteLine($"The current date is: {DateTime.Now:ddd MM/dd/yyyy}");
        Console.WriteLine("Enter the new date: (mm-dd-yy) ");
        Console.ReadLine();   // accept and ignore, like a plain Enter in cmd
    }

    private static void TimeCmd(string arg)
    {
        if (arg.Trim().Equals("/t", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine($"{DateTime.Now:hh:mm tt}");
            return;
        }
        Console.WriteLine($"The current time is: {DateTime.Now:HH:mm:ss.ff}");
        Console.WriteLine("Enter the new time: ");
        Console.ReadLine();
    }

    /// <summary>
    /// Reads this machine's real Windows version the way cmd does: the build
    /// number plus the UBR (update build revision) from the registry, e.g.
    /// "10.0.26100.4652". Falls back to <see cref="Environment.OSVersion"/> if
    /// the registry can't be read.
    /// </summary>
    private static string DetectWinVer()
    {
        var v = Environment.OSVersion.Version;
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            var build = key?.GetValue("CurrentBuildNumber") as string;
            if (!string.IsNullOrEmpty(build))
                return key?.GetValue("UBR") is int ubr
                    ? $"{v.Major}.{v.Minor}.{build}.{ubr}"
                    : $"{v.Major}.{v.Minor}.{build}";
        }
        catch { /* registry unreadable — fall through */ }
        return $"{v.Major}.{v.Minor}.{v.Build}.{v.Revision}";
    }

    /// <summary>Expands the $-codes of a cmd PROMPT template into the prompt.</summary>
    private static string BuildPrompt()
    {
        var t = _promptTemplate;
        var sb = new StringBuilder();
        for (var i = 0; i < t.Length; i++)
        {
            if (t[i] != '$' || i + 1 >= t.Length) { sb.Append(t[i]); continue; }
            switch (char.ToUpperInvariant(t[++i]))
            {
                case 'P': sb.Append(_cwd); break;
                case 'G': sb.Append('>'); break;
                case 'L': sb.Append('<'); break;
                case 'B': sb.Append('|'); break;
                case 'A': sb.Append('&'); break;
                case 'Q': sb.Append('='); break;
                case 'C': sb.Append('('); break;
                case 'F': sb.Append(')'); break;
                case 'S': sb.Append(' '); break;
                case '$': sb.Append('$'); break;
                case 'D': sb.Append($"{DateTime.Now:ddd MM/dd/yyyy}"); break;
                case 'T': sb.Append($"{DateTime.Now:HH:mm:ss.ff}"); break;
                case 'N': sb.Append(_cwd.Length > 0 ? _cwd[0] : 'C'); break;
                case 'V': sb.Append($"Microsoft Windows [Version {WinVer}]"); break;
                case '_': sb.Append('\n'); break;
                default: sb.Append('$').Append(t[i]); break;
            }
        }
        return sb.ToString();
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
            Restore();
            Console.WriteLine($"   {(string.IsNullOrEmpty(p.Path) ? p.Name : p.Path)}");
        }
        Console.WriteLine();
    }

    // ============================ console helpers ============================

    private static void Tag(string tag, ConsoleColor color, string rest)
    {
        Console.ForegroundColor = color;
        Console.Write("  " + tag + " ");
        Restore();
        Console.WriteLine(rest);
    }

    private static void WriteDim(string s)
    {
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.WriteLine(s);
        Restore();
    }

    /// <summary>Restores the colours chosen by the last COLOR command.</summary>
    private static void Restore()
    {
        Console.ForegroundColor = _fg;
        Console.BackgroundColor = _bg;
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
