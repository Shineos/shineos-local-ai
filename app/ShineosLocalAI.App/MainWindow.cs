// ShineosLocalAI.App - Open WebUI を WebView2 でラップするデスクトップアプリ
// - 起動: サービス起動確認 → /health 待ち → http://localhost:8080 を表示
// - 終了: サービスを停止（閉じたら localhost:8080 も閉じる）
// - ビルド: build.ps1（.NET Framework 4.x csc 使用・SDK 不要）
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using Microsoft.Web.WebView2.Wpf;

namespace ShineosLocalAI
{
    public class MainWindow : Window
    {
        const string ServiceName = "ShineosLocalAI";
        const string AppUrl = "http://localhost:8080";
        const string HealthUrl = AppUrl + "/health";

        readonly WebView2 webView = new WebView2();
        readonly Label status = new Label();
        readonly Button retryButton = new Button();
        bool closing;

        public MainWindow()
        {
            Title = "Shineos Local AI";
            Width = 1200;
            Height = 800;
            MinWidth = 800;
            MinHeight = 600;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = System.Windows.Media.Brushes.White;

            string ico = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "assets", "app.ico");
            try
            {
                if (File.Exists(ico))
                    Icon = new IconBitmapDecoder(new Uri(Path.GetFullPath(ico)), BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnLoad).Frames[0];
            }
            catch { }

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var top = new StackPanel { Orientation = Orientation.Horizontal };
            status.FontSize = 14;
            status.Padding = new Thickness(12, 8, 12, 8);
            status.VerticalContentAlignment = VerticalAlignment.Center;
            retryButton.Content = "再試行";
            retryButton.Margin = new Thickness(4, 6, 8, 6);
            retryButton.Padding = new Thickness(16, 2, 16, 2);
            retryButton.Visibility = Visibility.Collapsed;
            retryButton.Click += async (s, e) => { retryButton.Visibility = Visibility.Collapsed; await Startup(); };
            top.Children.Add(status);
            top.Children.Add(retryButton);
            Grid.SetRow(top, 0);
            grid.Children.Add(top);

            Grid.SetRow(webView, 1);
            grid.Children.Add(webView);
            Content = grid;

            Loaded += async (s, e) => { try { await Startup(); } catch (Exception ex) { ShowFatal("起動に失敗しました: " + ex.Message); } };
            Closed += (s, e) => StopService();
        }

        void SetStatus(string msg)
        {
            status.Content = "Shineos Local AI: " + msg;
        }

        bool IsServiceRunning()
        {
            string output = RunSc("query " + ServiceName);
            return output != null && output.Contains("RUNNING");
        }

        string RunSc(string args)
        {
            try
            {
                var psi = new ProcessStartInfo("sc.exe", args)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true
                };
                using (var p = Process.Start(psi))
                {
                    string output = p.StandardOutput.ReadToEnd();
                    if (!p.WaitForExit(10000))
                    {
                        try { p.Kill(); } catch { }
                        return null;
                    }
                    return output;
                }
            }
            catch { return null; }
        }

        bool ServiceExists()
        {
            string output = RunSc("query " + ServiceName);
            return output != null && (output.Contains("SERVICE_NAME") || output.Contains("RUNNING") || output.Contains("STOPPED"));
        }

        bool WaitForHealth(int timeoutSeconds)
        {
            var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
            while (DateTime.UtcNow < deadline)
            {
                try
                {
                    var req = (HttpWebRequest)WebRequest.Create(HealthUrl);
                    req.Timeout = 3000;
                    using (var resp = (HttpWebResponse)req.GetResponse())
                    {
                        if (resp.StatusCode == HttpStatusCode.OK)
                            return true;
                    }
                }
                catch { }
                Thread.Sleep(2000);
            }
            return false;
        }

        async Task Startup()
        {
            SetStatus("サービスを確認しています...");

            if (!ServiceExists())
            {
                ShowFatal("Shineos Local AI がインストールされていません。\nインストーラ（ShineosLocalAI-Setup.exe）を実行してください。");
                return;
            }

            if (!IsServiceRunning())
            {
                SetStatus("サービスを起動しています...");
                RunSc("start " + ServiceName);
            }

            SetStatus("Open WebUI の起動を待っています（初回は数分かかることがあります）...");
            bool ok = await Task.Run(() => WaitForHealth(180));
            if (!ok)
            {
                status.Content = "Shineos Local AI: 起動に失敗しました（サービスが応答しません）。";
                retryButton.Visibility = Visibility.Visible;
                return;
            }

            SetStatus("起動しました。");
            await webView.EnsureCoreWebView2Async(null);
            webView.Source = new Uri(AppUrl);
        }

        void StopService()
        {
            if (closing) return;
            closing = true;
            try { RunSc("stop " + ServiceName); } catch { }
        }

        void ShowFatal(string msg)
        {
            status.Content = "Shineos Local AI: " + msg.Replace("\n", "  ");
            retryButton.Visibility = Visibility.Collapsed;
        }
    }

    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            app.Run(new MainWindow());
        }
    }
}
