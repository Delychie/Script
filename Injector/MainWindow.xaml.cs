using System.IO;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;
using FsocietyInjector.Models;
using FsocietyInjector.Services;

namespace FsocietyInjector;

/// <summary>
/// A Command Prompt-style front end for the injector. Everything is driven by
/// typed commands (help, list, select, dll, inject…) printed into a console
/// view, so it reads like a real cmd.exe session rather than a GUI.
/// </summary>
public partial class MainWindow : Window
{
    private const string Prompt = "C:\\fsociety>";

    private List<ProcessModel> _procs = new();
    private ProcessModel? _target;
    private string? _dll;
    private bool _busy;

    private Paragraph _par = null!;

    // Console palette, pulled once from the theme.
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

    private void Echo(string cmd)
    {
        _par.Inlines.Add(new Run(Prompt) { Foreground = _fg });
        _par.Inlines.Add(new Run(cmd) { Foreground = _fg });
        _par.Inlines.Add(new LineBreak());
    }

    // ============================ boot ============================

    private void Boot()
    {
        Write("Microsoft Windows [Version 10.0.22631.4460]", _dim);
        Write("(c) Microsoft Corporation. All rights reserved.", _dim);
        Blank();
        Write("   com.fsociety // dll injector   v1.0  [x64]", _white);
        Tag("[+]", _green, "hello, friend.  type 'help' for commands.");
        Blank();
        RefreshProcs();
        PrintList();
    }

    // ============================ command loop ============================

    private void Cmd_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Return || _busy) return;
        e.Handled = true;
        var line = Cmd.Text;
        Cmd.Clear();
        Execute(line);
    }

    private void Execute(string raw)
    {
        var cmd = raw.Trim();
        Echo(cmd);
        if (cmd.Length == 0) return;

        var parts = cmd.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var verb = parts[0].ToLowerInvariant();
        var arg = parts.Length > 1 ? string.Join(' ', parts[1..]) : string.Empty;

        switch (verb)
        {
            case "help": case "?": Help(); break;
            case "list": case "ls": case "ps": RefreshProcs(); PrintList(); break;
            case "refresh":
                RefreshProcs();
                Tag("[+]", _green, $"{_procs.Count} processes."); Blank();
                break;
            case "select": case "sel": Select(arg); break;
            case "dll": case "payload": SetDll(arg); break;
            case "browse": Browse(); break;
            case "inject": Inject(); break;
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
        Write("    list                 enumerate running processes");
        Write("    select <# | pid>     choose a target process");
        Write("    dll <path>           set the payload dll");
        Write("    browse               pick a payload with a file dialog");
        Write("    inject               inject the payload into the target");
        Write("    refresh              re-scan processes");
        Write("    cls                  clear the screen");
        Write("    ver                  version info");
        Write("    exit                 close");
        Blank();
    }

    // ============================ commands ============================

    private void RefreshProcs() => _procs = ProcessService.Enumerate().ToList();

    private void PrintList()
    {
        Blank();
        Write("   #   PID     ARCH   PROCESS", _dim);
        Write("   --  ------  -----  ------------------------------", _dim);
        for (var i = 0; i < _procs.Count; i++)
        {
            var p = _procs[i];
            var sel = _target is not null && _target.Id == p.Id ? "*" : " ";
            var num = (i + 1).ToString().PadRight(3);
            var pid = p.Id.ToString().PadRight(6);
            var arch = p.ArchLabel.PadRight(4);
            var archBrush = p.ArchLabel == "x86" ? _yellow : _green;

            _par.Inlines.Add(new Run($"   {num}{sel} {pid}  ") { Foreground = _fg });
            _par.Inlines.Add(new Run(arch) { Foreground = archBrush });
            _par.Inlines.Add(new Run($"   {p.Name}") { Foreground = _fg });
            _par.Inlines.Add(new LineBreak());
        }
        Blank();
        Out.ScrollToEnd();
    }

    private void Select(string arg)
    {
        if (string.IsNullOrWhiteSpace(arg))
        {
            Tag("[x]", _red, "usage: select <# | pid>"); Blank(); return;
        }

        ProcessModel? p = null;
        if (int.TryParse(arg, out var n))
        {
            if (n >= 1 && n <= _procs.Count) p = _procs[n - 1];
            else p = _procs.FirstOrDefault(x => x.Id == n); // treat as a PID
        }

        if (p is null)
        {
            Tag("[x]", _red, $"no such process: {arg}"); Blank(); return;
        }

        _target = p;
        Tag("[+]", _green, $"target set: {p.Name} ({p.Id}) [{p.ArchLabel}]");
        if (p.ArchLabel == "x86")
            Tag("[!]", _yellow, "target is 32-bit; this injector is x64 and can only load into x64.");
        Blank();
    }

    private void SetDll(string arg)
    {
        if (string.IsNullOrWhiteSpace(arg))
        {
            Tag("[x]", _red, "usage: dll <path>"); Blank(); return;
        }
        _dll = arg.Trim('"');
        Tag("[+]", _green, $"payload set: {Path.GetFileName(_dll)}");
        if (!File.Exists(_dll))
            Tag("[!]", _yellow, "that path does not exist yet.");
        Blank();
    }

    private void Browse()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Select a DLL to inject",
            Filter = "Dynamic link libraries (*.dll)|*.dll|All files (*.*)|*.*",
            CheckFileExists = true,
        };
        if (dlg.ShowDialog(this) == true)
        {
            _dll = dlg.FileName;
            Tag("[+]", _green, $"payload set: {Path.GetFileName(_dll)}");
            Blank();
        }
    }

    private async void Inject()
    {
        if (_target is null) { Tag("[x]", _red, "no target. use: select <#>"); Blank(); return; }
        if (string.IsNullOrEmpty(_dll)) { Tag("[x]", _red, "no payload. use: dll <path> or browse"); Blank(); return; }

        _busy = true;
        Cmd.IsEnabled = false;

        var f = Path.GetFileName(_dll);
        Write($"  [*] injecting {f} -> {_target.Name} ({_target.Id})...", _dim);

        var result = await InjectionService.InjectAsync(_target.Id, _dll);

        if (result.Success) Tag("[+]", _green, result.Message);
        else                Tag("[x]", _red, result.Message);
        Blank();

        _busy = false;
        Cmd.IsEnabled = true;
        Cmd.Focus();
    }
}
