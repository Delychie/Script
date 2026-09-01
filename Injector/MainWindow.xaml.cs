using System.IO;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using FsocietyInjector.Models;
using FsocietyInjector.Services;

namespace FsocietyInjector;

/// <summary>
/// A Command Prompt front end for the injector. Everything is typed into a
/// console view. The one way to inject is:
///
///     C:\fsociety>dll inject
///     DLL path: &lt;paste the .dll path&gt;
///     Process path: &lt;paste the target's .exe path&gt;
///
/// which resolves the running process from that exe path and injects.
/// </summary>
public partial class MainWindow : Window
{
    private const string CmdPrompt = "C:\\fsociety>";

    private enum Mode { Command, AskDll, AskProc }

    private List<ProcessModel> _procs = new();
    private Mode _mode = Mode.Command;
    private string? _pendingDll;
    private bool _busy;

    private Paragraph _par = null!;
    private Brush _fg = null!, _dim = null!, _white = null!, _green = null!, _red = null!, _yellow = null!;

    public MainWindow()
    {
        InitializeComponent();

        _fg     = (Brush)FindResource("FgBrush");
        _dim    = (Brush)FindResource("DimBrush");
        _white  = (Brush)FindResource("WhiteBrush");
        _green  = (Brush)FindResource("GreenBrush");
        _red    = (Brush)FindResource("RedBrush");
        _yellow = (Brush)FindResource("YellowBrush");

        _par = new Paragraph { Margin = new Thickness(0) };
        Doc.Blocks.Clear();
        Doc.Blocks.Add(_par);

        Loaded += (_, _) => { Boot(); Cmd.Focus(); };
    }

    // ============================ window chrome ============================

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2) { ToggleMax(); return; }
        if (e.ButtonState == MouseButtonState.Pressed) DragMove();
    }

    private void BtnMin_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void BtnMax_Click(object sender, RoutedEventArgs e) => ToggleMax();
    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void ToggleMax() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    // ============================ console output ============================

    private void Write(string text, Brush? brush = null)
    {
        _par.Inlines.Add(new Run(text) { Foreground = brush ?? _fg });
        _par.Inlines.Add(new LineBreak());
        Out.ScrollToEnd();
    }

    private void Blank() => Write(string.Empty);

    /// <summary>A line whose leading tag (e.g. "[+]") is colored, rest default.</summary>
    private void Tag(string tag, Brush tagBrush, string rest)
    {
        _par.Inlines.Add(new Run("  " + tag + " ") { Foreground = tagBrush });
        _par.Inlines.Add(new Run(rest) { Foreground = _fg });
        _par.Inlines.Add(new LineBreak());
        Out.ScrollToEnd();
    }

    /// <summary>Prints the current prompt followed by what the user typed.</summary>
    private void Echo(string typed)
    {
        _par.Inlines.Add(new Run(PromptLabel.Text) { Foreground = _fg });
        _par.Inlines.Add(new Run(typed) { Foreground = _fg });
        _par.Inlines.Add(new LineBreak());
    }

    private void SetMode(Mode mode)
    {
        _mode = mode;
        PromptLabel.Text = mode switch
        {
            Mode.AskDll  => "DLL path: ",
            Mode.AskProc => "Process path: ",
            _            => CmdPrompt,
        };
    }

    // ============================ boot ============================

    private void Boot()
    {
        Write("Microsoft Windows [Version 10.0.22631.4460]", _dim);
        Write("(c) Microsoft Corporation. All rights reserved.", _dim);
        Blank();
        Write("   com.fsociety // dll injector   v1.0  [x64]", _white);
        Tag("[+]", _green, "hello, friend.");
        Write("      to inject:  dll inject   then paste the dll path and the process path.");
        Write("      type 'help' for all commands, 'list' to see running processes.", _dim);
        Blank();
    }

    // ============================ command loop ============================

    private void Cmd_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Return || _busy) return;
        e.Handled = true;

        var text = Cmd.Text;
        Cmd.Clear();
        Echo(text);

        switch (_mode)
        {
            case Mode.AskDll:  HandleDllPath(text.Trim().Trim('"')); break;
            case Mode.AskProc: HandleProcPath(text.Trim().Trim('"')); break;
            default:           Execute(text.Trim()); break;
        }
    }

    private void Execute(string cmd)
    {
        if (cmd.Length == 0) return;

        var parts = cmd.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var verb = parts[0].ToLowerInvariant();
        var arg = parts.Length > 1 ? string.Join(' ', parts[1..]) : string.Empty;

        switch (verb)
        {
            case "dll": case "inject":
                StartInjectFlow(verb, arg);
                break;
            case "help": case "?": Help(); break;
            case "list": case "ls": case "ps": RefreshProcs(); PrintList(); break;
            case "refresh":
                RefreshProcs();
                Tag("[+]", _green, $"{_procs.Count} processes."); Blank();
                break;
            case "cls": case "clear": _par.Inlines.Clear(); break;
            case "ver": Write("  fsociety injector  v1.0  [x64]  —  hello, friend."); Blank(); break;
            case "whoami": Write("  fsociety\\friend"); Blank(); break;
            case "exit": Write("  bye, friend.", _dim); Close(); break;
            default:
                Write($"  '{verb}' is not recognized. type 'help'.", _fg); Blank(); break;
        }
    }

    private void Help()
    {
        Blank();
        Write("  commands", _white);
        Write("    dll inject           inject a dll (asks for the dll path, then the process path)");
        Write("    list                 enumerate running processes (with paths)");
        Write("    refresh              re-scan processes");
        Write("    cls                  clear the screen");
        Write("    ver                  version info");
        Write("    exit                 close");
        Blank();
    }

    // ============================ the inject flow ============================

    /// <summary>`dll inject` (optionally `dll inject &lt;path&gt;`) starts the flow.</summary>
    private void StartInjectFlow(string verb, string arg)
    {
        // Accept "dll inject", "dll inject <dllpath>", or bare "inject".
        if (verb == "dll")
        {
            var sub = arg.Split((char[]?)null, 2, StringSplitOptions.RemoveEmptyEntries);
            if (sub.Length == 0 || !sub[0].Equals("inject", StringComparison.OrdinalIgnoreCase))
            {
                Tag("[x]", _red, "usage: dll inject"); Blank(); return;
            }
            arg = sub.Length > 1 ? sub[1] : string.Empty;
        }

        if (!string.IsNullOrWhiteSpace(arg))
        {
            // A dll path was pasted on the same line — skip straight to the process.
            _pendingDll = arg.Trim().Trim('"');
            AskProcOrFail();
        }
        else
        {
            SetMode(Mode.AskDll);
        }
    }

    private void HandleDllPath(string path)
    {
        if (path.Length == 0) { Tag("[x]", _red, "cancelled."); Blank(); SetMode(Mode.Command); return; }
        _pendingDll = path;
        AskProcOrFail();
    }

    private void AskProcOrFail()
    {
        if (!File.Exists(_pendingDll))
        {
            Tag("[x]", _red, $"dll not found: {_pendingDll}"); Blank();
            SetMode(Mode.Command);
            return;
        }
        SetMode(Mode.AskProc);
    }

    private void HandleProcPath(string path)
    {
        SetMode(Mode.Command);

        if (path.Length == 0) { Tag("[x]", _red, "cancelled."); Blank(); return; }

        var target = ResolveProcess(path);
        if (target is null)
        {
            Tag("[x]", _red, $"process not running: {path}");
            Write("      (run 'list' to see running processes and their paths.)", _dim);
            Blank();
            return;
        }

        InjectInto(target, _pendingDll!);
    }

    /// <summary>
    /// Matches a running process from a pasted exe path — by full path first,
    /// then by file name, then by the raw string as a process name.
    /// </summary>
    private ProcessModel? ResolveProcess(string path)
    {
        RefreshProcs();
        var file = System.IO.Path.GetFileName(path);

        return _procs.FirstOrDefault(p =>
                   !string.IsNullOrEmpty(p.Path) &&
                   string.Equals(p.Path, path, StringComparison.OrdinalIgnoreCase))
            ?? _procs.FirstOrDefault(p =>
                   file.Length > 0 &&
                   string.Equals(p.Name, file, StringComparison.OrdinalIgnoreCase))
            ?? _procs.FirstOrDefault(p =>
                   string.Equals(p.Name, path, StringComparison.OrdinalIgnoreCase));
    }

    private async void InjectInto(ProcessModel target, string dll)
    {
        if (target.ArchLabel == "x86")
        {
            Tag("[x]", _red, $"{target.Name} is 32-bit; this injector is x64 and can only load into x64.");
            Blank();
            return;
        }

        _busy = true;
        Cmd.IsEnabled = false;

        var f = System.IO.Path.GetFileName(dll);
        Write($"  [*] injecting {f} -> {target.Name} ({target.Id})...", _dim);

        var result = await InjectionService.InjectAsync(target.Id, dll);

        if (result.Success) Tag("[+]", _green, result.Message);
        else                Tag("[x]", _red, result.Message);
        Blank();

        _busy = false;
        Cmd.IsEnabled = true;
        Cmd.Focus();
    }

    // ============================ process list ============================

    private void RefreshProcs() => _procs = ProcessService.Enumerate().ToList();

    private void PrintList()
    {
        Blank();
        Write("   PID     ARCH   PROCESS / PATH", _dim);
        Write("   ------  -----  --------------------------------------------", _dim);
        foreach (var p in _procs)
        {
            var pid = p.Id.ToString().PadRight(6);
            var arch = p.ArchLabel.PadRight(4);
            var archBrush = p.ArchLabel == "x86" ? _yellow : _green;

            _par.Inlines.Add(new Run($"   {pid}  ") { Foreground = _fg });
            _par.Inlines.Add(new Run(arch) { Foreground = archBrush });
            _par.Inlines.Add(new Run($"   {(string.IsNullOrEmpty(p.Path) ? p.Name : p.Path)}") { Foreground = _fg });
            _par.Inlines.Add(new LineBreak());
        }
        Blank();
        Out.ScrollToEnd();
    }
}
