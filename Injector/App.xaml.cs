using System.Windows;
using System.Windows.Threading;

namespace MrrpInjector;

public partial class App : Application
{
    public App()
    {
        // A misbehaving DLL or a revoked handle shouldn't take the whole UI
        // down — surface it and keep the window alive.
        DispatcherUnhandledException += OnUnhandledException;
    }

    private void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(
            e.Exception.Message,
            "mrrpbot society injector — something went wrong",
            MessageBoxButton.OK,
            MessageBoxImage.Warning);
        e.Handled = true;
    }
}
