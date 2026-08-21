// ShineosLocalAI.App - Open WebUI を WebView2 でラップするデスクトップアプリ
// - 起動: サービス起動確認 → /health 待ち → http://localhost:8080 を表示
// - 終了: サービスを停止（閉じたら localhost:8080 も閉じる）
// - ロード中は中央にスピナー付きメッセージを表示
// - ポート8080が他アプリに占有されている場合は誤表示せず中央にエラー表示
//   （サービスの子プロセス（python）が8080を持つ場合は「自サービス」と判定）
// - ビルド: build.ps1（.NET Framework 4.x csc 使用・SDK 不要）
using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using Microsoft.Web.WebView2.Wpf;

namespace ShineosLocalAI
{
    public class MainWindow : Window
    {
        const string ServiceName = "ShineosLocalAI";

        readonly string AppUrl;
        readonly string HealthUrl;
        readonly int Port;

        readonly WebView2 webView = new WebView2();
        readonly Grid overlay;
        readonly System.Windows.Shapes.Path spinner;
        readonly TextBlock overlayTitle;
        readonly TextBlock overlayMessage;
        readonly Button retryButton;
        bool closing;

        public MainWindow()
        {
            // 使用ポートを {app}\port.txt から読む（無ければ 8080）
            int port = 8080;
            try
            {
                string pf = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "port.txt");
                if (File.Exists(pf))
                {
                    string s = File.ReadAllText(pf).Trim();
                    int p;
                    if (int.TryParse(s, out p) && p > 0) port = p;
                }
            }
            catch { }
            Port = port;
            AppUrl = "http://localhost:" + Port;
            HealthUrl = AppUrl + "/health";

            Title = "Shineos Local AI";
            Width = 1200;
            Height = 800;
            MinWidth = 800;
            MinHeight = 600;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = Brushes.White;

            string ico = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "assets", "app.ico");
            try
            {
                if (File.Exists(ico))
                    Icon = new IconBitmapDecoder(new Uri(Path.GetFullPath(ico)), BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnLoad).Frames[0];
            }
            catch { }

            var root = new Grid();

            // WebView2
            root.Children.Add(webView);

            // 中央オーバーレイ（ローディング・エラー表示）
            overlay = new Grid
            {
                Background = new SolidColorBrush(Color.FromArgb(250, 255, 255, 255)),
                Visibility = Visibility.Visible
            };
            var center = new StackPanel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };

            // Material Design 風のリングスピナー（270° の円弧を滑らかに回転）
            spinner = new System.Windows.Shapes.Path
            {
                Width = 56,
                Height = 56,
                Stroke = new SolidColorBrush(Color.FromRgb(0x2B, 0x5C, 0xE3)),
                StrokeThickness = 5,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                Data = Geometry.Parse("M 28,2.5 A 25.5,25.5 0 1 1 2.5,28"),
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 20)
            };
            var spin = new RotateTransform(0);
            spinner.RenderTransform = spin;
            spin.BeginAnimation(RotateTransform.AngleProperty,
                new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(1000)) { RepeatBehavior = RepeatBehavior.Forever });

            overlayTitle = new TextBlock
            {
                Text = "Shineos Local AI",
                FontSize = 22,
                FontWeight = FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A)),
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 10)
            };

            overlayMessage = new TextBlock
            {
                FontSize = 14,
                Foreground = new SolidColorBrush(Color.FromRgb(0x66, 0x66, 0x66)),
                TextAlignment = TextAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = 640,
                HorizontalAlignment = HorizontalAlignment.Center
            };

            retryButton = new Button
            {
                Content = "再試行",
                FontSize = 15,
                Padding = new Thickness(30, 6, 30, 6),
                Margin = new Thickness(0, 26, 0, 0),
                HorizontalAlignment = HorizontalAlignment.Center,
                Visibility = Visibility.Collapsed
            };
            retryButton.Click += async (s, e) => { retryButton.Visibility = Visibility.Collapsed; ShowLoading("起動しています..."); await Startup(); };

            center.Children.Add(spinner);
            center.Children.Add(overlayTitle);
            center.Children.Add(overlayMessage);
            center.Children.Add(retryButton);
            overlay.Children.Add(center);
            root.Children.Add(overlay);

            Content = root;

            Loaded += async (s, e) => { try { await Startup(); } catch (Exception ex) { ShowError("起動に失敗しました: " + ex.Message, true); } };
            Closed += (s, e) => StopService();
            Application.Current.SessionEnding += (s, e) => { closing = true; };
        }

        void ShowLoading(string msg)
        {
            spinner.Visibility = Visibility.Visible;
            retryButton.Visibility = Visibility.Collapsed;
            overlayMessage.Text = msg;
            overlayMessage.Foreground = new SolidColorBrush(Color.FromRgb(0x66, 0x66, 0x66));
            overlay.Visibility = Visibility.Visible;
            overlay.Opacity = 1;
        }

        void ShowError(string msg, bool showRetry)
        {
            spinner.Visibility = Visibility.Collapsed;
            retryButton.Visibility = showRetry ? Visibility.Visible : Visibility.Collapsed;
            overlayMessage.Text = msg;
            overlayMessage.Foreground = new SolidColorBrush(Colors.DarkRed);
            overlay.Visibility = Visibility.Visible;
            overlay.Opacity = 1;
        }

        void HideOverlay()
        {
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(400));
            fade.Completed += (s, e) => overlay.Visibility = Visibility.Collapsed;
            overlay.BeginAnimation(OpacityProperty, fade);
        }

        void Log(string msg)
        {
            try
            {
                string f = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.log");
                File.AppendAllText(f, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + msg + Environment.NewLine);
            }
            catch { }
        }

        bool IsServiceRunning()
        {
            string output = RunSc("query " + ServiceName);
            return output != null && output.Contains("RUNNING");
        }

        int GetServicePid()
        {
            string output = RunSc("queryex " + ServiceName);
            if (output == null) return 0;
            foreach (string line in output.Split('\n'))
            {
                if (line.IndexOf("PID", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    Match m = Regex.Match(line, @"\d+");
                    if (m.Success)
                    {
                        int pid;
                        if (int.TryParse(m.Value, out pid)) return pid;
                    }
                }
            }
            return 0;
        }

        int GetParentPid(int pid)
        {
            try
            {
                var searcher = new ManagementObjectSearcher("SELECT ParentProcessId FROM Win32_Process WHERE ProcessId=" + pid);
                foreach (ManagementBaseObject obj in searcher.Get())
                    return Convert.ToInt32(obj["ParentProcessId"]);
            }
            catch { }
            return 0;
        }

        // pid の祖先チェーン（最大5世代）に svcPid が含まれるか
        bool IsDescendantOf(int pid, int svcPid)
        {
            int cur = pid;
            for (int i = 0; i < 5 && cur != 0; i++)
            {
                if (cur == svcPid) return true;
                cur = GetParentPid(cur);
            }
            return false;
        }

        int GetPortOwnerPid(int port)
        {
            try
            {
                var psi = new ProcessStartInfo("netstat.exe", "-ano")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true
                };
                using (var p = Process.Start(psi))
                {
                    string output = p.StandardOutput.ReadToEnd();
                    if (!p.WaitForExit(5000)) { try { p.Kill(); } catch { } return 0; }
                    foreach (string line in output.Split('\n'))
                    {
                        if (line.IndexOf(":" + port, StringComparison.Ordinal) >= 0 && line.IndexOf("LISTENING", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            string[] parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                            if (parts.Length >= 5)
                            {
                                int pid;
                                if (int.TryParse(parts[parts.Length - 1], out pid)) return pid;
                            }
                        }
                    }
                }
            }
            catch { }
            return 0;
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
            ShowLoading("Shineos Local AI を起動しています...");

            if (!ServiceExists())
            {
                ShowError("Shineos Local AI がインストールされていません。\n\nインストーラ（ShineosLocalAI-Setup.exe）を実行してください。", false);
                return;
            }

            // ポート占有チェック（サービス停止中なら 8080 を持つのは必ず別アプリ）
            // 占有されている場合はサービスを起動せずエラー表示する
            int svcPid = GetServicePid();
            int owner = GetPortOwnerPid(Port);
            Log("port " + Port + " owner pid=" + owner + " (service pid=" + svcPid + ")");
            if (owner != 0 && !(svcPid != 0 && IsDescendantOf(owner, svcPid)))
            {
                ShowError("ポート " + Port + " が他のアプリ（PID " + owner + "）で使用されています。\n\n" +
                          "そのアプリを終了してから「再試行」を押してください。", true);
                return;
            }

            if (!IsServiceRunning())
            {
                ShowLoading("サービスを起動しています...");
                RunSc("start " + ServiceName);
            }

            svcPid = 0;
            var deadline = DateTime.UtcNow.AddSeconds(30);
            while (DateTime.UtcNow < deadline)
            {
                svcPid = GetServicePid();
                if (svcPid != 0) break;
                Thread.Sleep(1000);
            }
            Log("service pid=" + svcPid);

            ShowLoading("Open WebUI の起動を待っています（初回は数分かかることがあります）...");
            bool ok = await Task.Run(() => WaitForHealth(240));
            if (!ok)
            {
                ShowError("起動に失敗しました（サービスが応答しません）。\n\nログ: " + Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "logs", "openwebui.err.log"), true);
                return;
            }

            owner = GetPortOwnerPid(Port);
            svcPid = GetServicePid();
            Log("final port owner pid=" + owner + " (service pid=" + svcPid + ", descendant=" + (owner != 0 && IsDescendantOf(owner, svcPid)) + ")");

            if (owner != 0 && !IsDescendantOf(owner, svcPid))
            {
                ShowError("ポート " + Port + " が他のアプリ（PID " + owner + "）で使用されています。\n\n" +
                          "そのアプリを終了してから「再試行」を押してください。", true);
                return;
            }

            HideOverlay();
            await webView.EnsureCoreWebView2Async(null);
            webView.Source = new Uri(AppUrl);
        }

        void StopService()
        {
            if (closing) return;
            closing = true;
            try { RunSc("stop " + ServiceName); } catch { }
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
