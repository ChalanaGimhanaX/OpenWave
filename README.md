# OpenWave

**One-command proxy tunnel for restricted university & workplace networks.**

No installs, no GUI, no technical knowledge required — just paste one line into PowerShell and you're connected.

---

## Quick Start

Open **PowerShell** and paste this:

```powershell
irm https://raw.githubusercontent.com/ChalanaGimhanaX/OpenWave/main/connect.ps1 | iex
```

That's it. OpenWave will download everything it needs, set up the tunnel, and tell you when you're connected.

> **Press Enter at any time to disconnect** and everything is restored automatically.

---

## What Happens When You Run It

1. **Downloads Xray** — the tunnel engine is downloaded once and saved to `~/.openwave/`. Future runs are instant.
2. **Picks a server** — choose from your saved servers or paste in a new one.
3. **Starts the tunnel** — routes your traffic through the server.
4. **Sets your system proxy** — all browsers and apps automatically use the tunnel.
5. **Watches for crashes** — a background watchdog monitors the script. Even if you force-quit or Task Manager kills it, the watchdog cleans up your proxy settings so your internet is never left broken.
6. **Disconnects cleanly** — press Enter and all settings are restored.

---

## Supported Server Types

You can paste any of these link formats:

| Protocol | Format |
|----------|--------|
| **VLESS** | `vless://uuid@host:port?...#Name` |
| **VMESS** | `vmess://base64encodedstring` |
| **Trojan** | `trojan://password@host:port?...#Name` |

All transport types are supported: TCP, WebSocket, gRPC, HTTP/2, and all security modes (TLS, Reality, None).

---

## If Chrome Isn't Using the Tunnel

Some Chrome extensions (like VPNs or privacy shields) control their own proxy settings and can override the system tunnel. OpenWave will automatically detect these and show you a list.

**To fix it:**
1. Click the **puzzle-piece icon** in the top-right corner of Chrome
2. Turn **OFF** any VPN or proxy extensions shown in the list
3. Turn them back **ON** when you're done

---

## Managing Your Servers

```powershell
# Open the server manager
.\manage.ps1
```

From there you can add, remove, and list your saved servers, or connect directly.

---

## File Structure

```
~/.openwave/
├── xray/            # Xray engine (auto-downloaded)
│   └── xray.exe
├── config.json      # Auto-generated config
└── servers.txt      # Your saved server links
```

---

## Uninstall

```powershell
# Via the manager
.\manage.ps1        # Select [5] Uninstall

# Or manually
Remove-Item -Recurse -Force "$env:USERPROFILE\.openwave"
```

---

## Notes

- **No admin required** — runs entirely as a regular user
- **Crash-safe** — the WMI watchdog ensures your proxy is always restored even if the window is force-closed
- **First run needs internet** — Xray is downloaded from GitHub. If GitHub is blocked, manually place `xray.exe` in `~/.openwave/xray/`
- **Default server included** — works out of the box without any configuration
