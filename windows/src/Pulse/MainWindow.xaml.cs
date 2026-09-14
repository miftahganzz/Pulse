using System;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Pulse;

public partial class MainWindow : Window
{
    private bool _isIpMasked = true;

    public MainWindow()
    {
        this.InitializeComponent();

        // Enable Windows 11 Mica Backdrop
        if (MicaController.IsSupported())
        {
            this.SystemBackdrop = new MicaBackdrop();
        }

        // Extend content into titlebar
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        // Set native Windows window icon
        try
        {
            AppWindow.SetIcon("Assets/AppIcon.ico");
        }
        catch { }
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem item)
        {
            string tag = item.Tag?.ToString() ?? "";
            TitleBarHeading.Text = tag switch
            {
                "ALL_SERVERS" => "All Servers",
                "COMPARE_SERVERS" => "Compare Servers",
                "INFRA_MAP" => "Infrastructure Map",
                _ => item.Content?.ToString() ?? "Pulse"
            };
        }
    }

    private void OnAddServerClick(object sender, RoutedEventArgs e)
    {
        // Open Add Server Dialog
    }

    private void OnSearchClick(object sender, RoutedEventArgs e)
    {
        // Open Command Palette / Quick Search (Ctrl+K)
    }

    private void OnMaskIpClick(object sender, RoutedEventArgs e)
    {
        _isIpMasked = !_isIpMasked;
        MaskIpBtn.Content = new FontIcon { Glyph = _isIpMasked ? "\uE890" : "\uED1A", FontSize = 14 };
    }

    private void OnDocsClick(object sender, RoutedEventArgs e)
    {
        // Open documentation window / link
    }

    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        // Open Settings Dialog
    }
}
