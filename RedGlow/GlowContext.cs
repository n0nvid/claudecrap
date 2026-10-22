using System.Net.NetworkInformation;

namespace RedGlow;

/// <summary>
/// Shows a red glow around every screen while this machine has a route to a real network,
/// i.e. GoDark.ps1 has not been run. VMware adapters (the REMnux link) don't count.
/// </summary>
sealed class GlowContext : ApplicationContext
{
    readonly List<GlowWindow> _windows = [];
    readonly NotifyIcon _tray;
    readonly ToolStripMenuItem _status;
    readonly System.Windows.Forms.Timer _timer;
    string _screenLayout = "";
    bool? _online;

    public GlowContext()
    {
        _status = new ToolStripMenuItem { Enabled = false };
        var menu = new ContextMenuStrip();
        menu.Items.Add(_status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitThread());

        _tray = new NotifyIcon { Icon = SystemIcons.Shield, ContextMenuStrip = menu, Visible = true };

        _timer = new System.Windows.Forms.Timer { Interval = 2000 };
        _timer.Tick += (_, _) => Update();
        _timer.Start();
        Update();
    }

    void Update()
    {
        // Rebuild the overlays when monitors are added, removed or resized.
        string layout = string.Join("|", Screen.AllScreens.Select(s => s.Bounds));
        if (layout != _screenLayout)
        {
            _screenLayout = layout;
            foreach (var w in _windows) w.Dispose();
            _windows.Clear();
            _windows.AddRange(Screen.AllScreens.Select(s => new GlowWindow(s.Bounds)));
            _online = null;
        }

        bool online = IsOnline();
        if (online != _online)
        {
            _online = online;
            foreach (var w in _windows) w.Visible = online;
            string text = online ? "ONLINE - not dark" : "DARK - no route to a real network";
            _status.Text = text;
            _tray.Text = "RedGlow: " + text;
        }

        if (online)
            foreach (var w in _windows) w.KeepOnTop();
    }

    static bool IsOnline() =>
        NetworkInterface.GetAllNetworkInterfaces().Any(n =>
            n.OperationalStatus == OperationalStatus.Up &&
            n.NetworkInterfaceType is not (NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) &&
            !n.Description.StartsWith("VMware Virtual Ethernet Adapter", StringComparison.OrdinalIgnoreCase) &&
            n.GetIPProperties().GatewayAddresses.Count > 0);

    protected override void ExitThreadCore()
    {
        _timer.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
        foreach (var w in _windows) w.Dispose();
        base.ExitThreadCore();
    }
}
