using Microsoft.UI.Xaml;

namespace Pulse;

public partial class App : Application
{
    private Window? _mainWindow;

    public App()
    {
        this.InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }
}
