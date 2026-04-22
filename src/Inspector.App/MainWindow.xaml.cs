using System.Windows;
using Inspector.App.ViewModels;

namespace Inspector.App;

public partial class MainWindow : Window
{
    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
        Loaded += async (_, _) => await viewModel.RefreshAsync();
    }
}
