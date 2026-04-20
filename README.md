# OpenWave

**One-command V2Ray tunnel for restricted university WiFi networks.**

No third-party GUI software needed — just a single PowerShell command.

---

## Quick Start

### One-Liner (copy-paste into PowerShell)

```powershell
irm https://raw.githubusercontent.com/ChalanaGimhanaX/OpenWave/main/connect.ps1 | iex
```

### Local Run

```powershell
# Connect with interactive server selection (default server included)
.\connect.ps1

# Connect with a specific VLESS URI
.\connect.ps1 -VlessUri "vless://uuid@host:port?type=ws&security=tls&sni=example.com#MyServer"

# Manage saved servers
.\manage.ps1
```

---

## What It Does

1. **Downloads V2Ray Core** — Fetches `v2ray-core` binary from GitHub (only once, cached in `~/.openwave/`)
2. **Parses your VLESS URI** — Supports all transport types (TCP, WebSocket, gRPC, H2) and security modes (TLS, Reality, None)
3. **Generates config** — Creates a proper V2Ray JSON config with SOCKS5 + HTTP inbounds
4. **Starts Local Proxy** — Runs V2Ray in the background
5. **Sets System Proxy** — Automatically configures Windows HTTP proxy so all apps route through the tunnel
6. **Cleans Up** — When you disconnect, it stops V2Ray and restores your original proxy settings

---

## Supported VLESS Configurations

| Feature | Support |
|---------|---------|
| **Transport** | TCP, WebSocket, gRPC, HTTP/2 |
| **Security** | TLS, Reality, None |
| **Fingerprint** | Chrome, Firefox, Safari, etc. |
| **Flow** | xtls-rprx-vision |
| **ALPN** | h2, http/1.1 |

### VLESS URI Format

```
vless://UUID@ADDRESS:PORT?type=TRANSPORT&security=SECURITY&sni=SNI&fp=FINGERPRINT#REMARK
```

**Examples:**

```
# WebSocket + TLS
vless://xxxx-xxxx@example.com:443?type=ws&security=tls&sni=example.com&path=%2Fws#MyServer

# Reality
vless://xxxx-xxxx@1.2.3.4:443?type=tcp&security=reality&sni=www.google.com&fp=chrome&pbk=XXXXX&sid=XXXX&flow=xtls-rprx-vision#RealityServer

# gRPC + TLS
vless://xxxx-xxxx@example.com:443?type=grpc&security=tls&sni=example.com&serviceName=mygrpc#gRPC-Server
```

---

## File Structure

```
~/.openwave/
├── v2ray/           # V2Ray core binary (auto-downloaded)
│   ├── v2ray.exe
│   ├── geoip.dat
│   └── geosite.dat
├── config.json      # Auto-generated V2Ray config
└── servers.txt      # Saved VLESS server URIs
```

---

## Uninstall

```powershell
# Via manager
.\manage.ps1
# Select option [5] Uninstall

# Or manually
Remove-Item -Recurse -Force "$env:USERPROFILE\.openwave"
```

---

## Notes

- **Admin not required** — runs entirely in user space
- **Proxy scope** — sets Windows system HTTP proxy, which covers browsers and most apps. Some apps (like terminal tools) may need manual SOCKS5 config at `127.0.0.1:10808`
- **GitHub access** — initial download requires access to `github.com`. If blocked, manually place `v2ray.exe` in `~/.openwave/v2ray/`
- **Default server included** — a built-in VLESS server is provided so you can connect without any configuration
