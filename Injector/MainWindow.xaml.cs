using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;
using FsocietyInjector.Models;
using FsocietyInjector.Services;

namespace FsocietyInjector;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<ProcessModel> _visible = new();
    private readonly ObservableCollection<LogEntry> _log = new();
    private List<ProcessModel> _all = new();

    private ProcessModel? _selected;
    private string? _dllPath;

    // Brushes pulled once from the merged theme so the log stays on-palette.
    private readonly Brush _mint;
    private readonly Brush _pink;
    private readonly Brush _red;
    private readonly Brush _muted;

    public MainWindow()
    {
        InitializeComponent();

        _mint  = (Brush)FindResource("AccentCBrush");
        _pink  = (Brush)FindResource("AccentBBrush");
        _red   = (Brush)FindResource("DangerBrush");
        _muted = (Brush)FindResource("Text1Brush");

        ProcListBox.ItemsSource = _visible;
        LogList.ItemsSource = _log;

        Loaded += (_, _) =>
        {
            RefreshProcesses();
            Log("hello, friend. select a target and a payload to begin.", _mint);
        };
    }

    // ============================ window chrome ============================

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
            DragMove();
    }

    private void BtnMin_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    // ============================ process list ============================

    private void BtnRefresh_Click(object sender, RoutedEventArgs e) => RefreshProcesses();

    private void RefreshProcesses()
    {
        var keepId = _selected?.Id;

        _all = ProcessService.Enumerate().ToList();
        ApplyFilter(SearchBox.Text);

        ProcCount.Text = $"{_all.Count} running";

        // Re-select the previous target if it's still around.
        if (keepId is int id)
        {
            var again = _visible.FirstOrDefault(p => p.Id == id);
            if (again is not null) ProcListBox.SelectedItem = again;
        }
    }

    private void SearchBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        SearchHint.Visibility = string.IsNullOrEmpty(SearchBox.Text)
            ? Visibility.Visible : Visibility.Collapsed;
        ApplyFilter(SearchBox.Text);
    }

    private void ApplyFilter(string query)
    {
        _visible.Clear();
        var q = query?.Trim() ?? string.Empty;

        foreach (var p in _all)
        {
            if (q.Length == 0
                || p.Name.Contains(q, StringComparison.OrdinalIgnoreCase)
                || p.Id.ToString().Contains(q))
            {
                _visible.Add(p);
            }
        }
    }

    private void ProcListBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        _selected = ProcListBox.SelectedItem as ProcessModel;
        UpdateReadiness();
        UpdateArchWarning();

        if (_selected is not null)
            SetStatus($"target · {_selected.Name} ({_selected.Id})", _pink);
    }

    // ============================ payload ============================

    private void BtnBrowse_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Select a DLL to inject",
            Filter = "Dynamic link libraries (*.dll)|*.dll|All files (*.*)|*.*",
            CheckFileExists = true,
        };

        if (dlg.ShowDialog(this) == true)
        {
            _dllPath = dlg.FileName;
            DllPathBox.Text = _dllPath;
            Log($"payload set · {Path.GetFileName(_dllPath)}", _muted);
            UpdateReadiness();
            UpdateArchWarning();
        }
    }

    // ============================ inject ============================

    private async void BtnInject_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null || string.IsNullOrEmpty(_dllPath))
            return;

        SetBusy(true);
        SetStatus("injecting…", _pink);
        Log($"injecting {Path.GetFileName(_dllPath)} → {_selected.Name} ({_selected.Id})…", _muted);

        var result = await InjectionService.InjectAsync(_selected.Id, _dllPath);

        if (result.Success)
        {
            Log("✓ " + result.Message, _mint);
            SetStatus("injected", _mint);
        }
        else
        {
            Log("✕ " + result.Message, _red);
            SetStatus("failed", _red);
        }

        SetBusy(false);
    }

    // ============================ helpers ============================

    private void UpdateReadiness()
    {
        BtnInject.IsEnabled = _selected is not null
                              && !string.IsNullOrEmpty(_dllPath)
                              && File.Exists(_dllPath);
    }

    /// <summary>
    /// A 64-bit injector can only load a 64-bit DLL into a 64-bit process.
    /// We can't read the DLL's bitness without parsing its PE header, so we
    /// warn on the one mismatch we *can* see: an x86 target.
    /// </summary>
    private void UpdateArchWarning()
    {
        if (_selected is { ArchLabel: "x86" })
        {
            ArchWarning.Text =
                "⚠ This target is 32-bit (x86). This injector is x64 and can only " +
                "inject into 64-bit processes — pick an x64 target.";
            ArchWarning.Visibility = Visibility.Visible;
        }
        else
        {
            ArchWarning.Visibility = Visibility.Collapsed;
        }
    }

    private void SetBusy(bool busy)
    {
        BtnInject.IsEnabled = !busy && _selected is not null && !string.IsNullOrEmpty(_dllPath);
        BtnBrowse.IsEnabled = !busy;
        BtnRefresh.IsEnabled = !busy;
        ProcListBox.IsEnabled = !busy;
    }

    private void SetStatus(string text, Brush brush)
    {
        StatusText.Text = text;
        StatusDot.Fill = brush;
    }

    private void Log(string text, Brush brush)
    {
        _log.Add(new LogEntry(DateTime.Now.ToString("HH:mm:ss"), text, brush));
        LogScroller.ScrollToEnd();
    }

    private sealed record LogEntry(string Time, string Text, Brush Brush);
}
