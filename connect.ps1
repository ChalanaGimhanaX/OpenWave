<#
.SYNOPSIS
    OpenWave - One-click Xray/VLESS tunnel for restricted networks.
.DESCRIPTION
    Run with:  irm https://your-host.com/connect.ps1 | iex
    Or locally: .\connect.ps1
    Or with a VLESS URI: .\connect.ps1 -VlessUri "vless://..."
#>

param(
    [string]$VlessUri
)

# ── Branding ─────────────────────────────────────────────────────────────────
$Banner = @"

   ██████╗ ██████╗ ███████╗███╗   ██╗██╗    ██╗ █████╗ ██╗   ██╗███████╗
  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██║    ██║██╔══██╗██║   ██║██╔════╝
  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║ █╗ ██║███████║██║   ██║█████╗
  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝
  ╚██████╔╝██║     ███████╗██║ ╚████║╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗
   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝ ╚══════╝
                     Bypass restrictions. Stay connected.

"@

# ── Config ───────────────────────────────────────────────────────────────────
$XrayVersion    = "25.5.16"
$XrayZipUrl     = "https://github.com/XTLS/Xray-core/releases/download/v$XrayVersion/Xray-windows-64.zip"
$InstallDir     = "$env:USERPROFILE\.openwave"
$XrayDir        = "$InstallDir\xray"
$XrayExe        = "$XrayDir\xray.exe"
$ConfigPath     = "$InstallDir\config.json"
$LocalSocksPort = 10808
$LocalHttpPort  = 10809

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-C {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Write-Step {
    param([string]$Icon, [string]$Text)
    Write-Host "  $Icon " -NoNewline -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor White
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  [OK] " -NoNewline -ForegroundColor Green
    Write-Host $Text -ForegroundColor Gray
}

function Write-Err {
    param([string]$Text)
    Write-Host "  [!!] " -NoNewline -ForegroundColor Red
    Write-Host $Text -ForegroundColor White
}

function Write-Separator {
    Write-Host ("  " + ("-" * 62)) -ForegroundColor DarkGray
}

# Helper: get value from hashtable with default (treats empty string as missing)
function Get-ParamOrDefault {
    param([hashtable]$Params, [string]$Key, [string]$Default)
    if ($Params.ContainsKey($Key) -and $Params[$Key] -ne "") { return $Params[$Key] }
    return $Default
}

# ── VLESS URI Parser ────────────────────────────────────────────────────────
# Format: vless://uuid@host:port?type=tcp&security=tls&sni=example.com&fp=chrome&encryption=none#Name
function Parse-VlessUri {
    param([string]$Uri)

    if (-not $Uri.StartsWith("vless://")) {
        Write-Err "Invalid VLESS URI - must start with 'vless://'"
        return $null
    }

    $stripped = $Uri.Substring(8)

    # Split off the fragment (#Name)
    $hashIdx = $stripped.LastIndexOf('#')
    if ($hashIdx -ge 0) {
        $main   = $stripped.Substring(0, $hashIdx)
        $remark = [System.Uri]::UnescapeDataString($stripped.Substring($hashIdx + 1))
    } else {
        $main   = $stripped
        $remark = "OpenWave Server"
    }

    # Split UUID from rest
    $atIdx = $main.IndexOf('@')
    if ($atIdx -lt 0) {
        Write-Err "Cannot parse UUID from VLESS URI"
        return $null
    }
    $uuid = $main.Substring(0, $atIdx)
    $rest = $main.Substring($atIdx + 1)

    # Split host:port from query
    $qIdx = $rest.IndexOf('?')
    if ($qIdx -ge 0) {
        $hostPort = $rest.Substring(0, $qIdx)
        $queryStr = $rest.Substring($qIdx + 1)
    } else {
        $hostPort = $rest
        $queryStr = ""
    }
    # Strip trailing slash (some clients add /path before ?)
    $hostPort = $hostPort.TrimEnd('/')

    # Parse host and port (handle IPv6)
    $addr = $null
    $port = 443
    if ($hostPort -match '^\[(.+)\]:(\d+)$') {
        $addr = $Matches[1]
        $port = [int]$Matches[2]
    } elseif ($hostPort -match '^(.+):(\d+)$') {
        $addr = $Matches[1]
        $port = [int]$Matches[2]
    } else {
        Write-Err "Cannot parse host:port from VLESS URI"
        return $null
    }

    # Parse query parameters
    $params = @{}
    if ($queryStr -ne "") {
        $pairs = $queryStr.Split('&')
        foreach ($pair in $pairs) {
            $eqIdx = $pair.IndexOf('=')
            if ($eqIdx -gt 0) {
                $k = $pair.Substring(0, $eqIdx)
                # Replace + with space (form-encoded), then URL-decode
                $rawVal = $pair.Substring($eqIdx + 1).Replace('+', ' ')
                $v = [System.Uri]::UnescapeDataString($rawVal)
                $params[$k] = $v
            }
        }
    }

    $result = @{
        UUID        = $uuid
        Address     = $addr
        Port        = $port
        Remark      = $remark
        Type        = (Get-ParamOrDefault $params 'type'        'tcp')
        Security    = (Get-ParamOrDefault $params 'security'    'none')
        SNI         = (Get-ParamOrDefault $params 'sni'         $addr)
        ALPN        = (Get-ParamOrDefault $params 'alpn'        '')
        Path        = (Get-ParamOrDefault $params 'path'        '/')
        Host        = (Get-ParamOrDefault $params 'host'        $addr)
        Fingerprint = (Get-ParamOrDefault $params 'fp'          'chrome')
        PbkKey      = (Get-ParamOrDefault $params 'pbk'         '')
        Sid         = (Get-ParamOrDefault $params 'sid'         '')
        Flow        = (Get-ParamOrDefault $params 'flow'        '')
        HeaderType  = (Get-ParamOrDefault $params 'headerType'  'none')
        Encryption  = (Get-ParamOrDefault $params 'encryption'  'none')
        SpiderX     = (Get-ParamOrDefault $params 'spx'         '')
        ServiceName = (Get-ParamOrDefault $params 'serviceName' '')
        Mode        = (Get-ParamOrDefault $params 'mode'        'gun')
    }
    return $result
}

# ── Config Generator ────────────────────────────────────────────────────────
function Generate-XrayConfig {
    param([hashtable]$Server)

    # Build stream settings based on transport type
    $streamSettings = @{
        network = $Server.Type
    }

    # ── Transport settings ──
    switch ($Server.Type) {
        "ws" {
            $streamSettings["wsSettings"] = @{
                path = $Server.Path
                headers = @{
                    Host = $Server.Host
                }
            }
        }
        "grpc" {
            $streamSettings["grpcSettings"] = @{
                serviceName = $Server.ServiceName
                multiMode   = ($Server.Mode -eq "multi")
            }
        }
        "h2" {
            $streamSettings["httpSettings"] = @{
                path = $Server.Path
                host = @($Server.Host)
            }
        }
        "tcp" {
            if ($Server.HeaderType -eq "http") {
                $streamSettings["tcpSettings"] = @{
                    header = @{
                        type = "http"
                        request = @{
                            path = @($Server.Path)
                            headers = @{ Host = @($Server.Host) }
                        }
                    }
                }
            }
        }
    }

    # ── Security / TLS settings ──
    switch ($Server.Security) {
        "tls" {
            $streamSettings["security"] = "tls"
            $tlsSettings = @{
                serverName  = $Server.SNI
                fingerprint = $Server.Fingerprint
            }
            # Allow insecure when SNI differs from server address (CDN fronting)
            if ($Server.SNI -ne $Server.Address) {
                $tlsSettings["allowInsecure"] = $true
            }
            if ($Server.ALPN -ne "") {
                $alpnValues = @()
                foreach ($a in ($Server.ALPN -split ',')) {
                    $trimmed = $a.Trim()
                    # Filter out h3 (QUIC) when using TCP transport - incompatible
                    if ($trimmed -eq "h3" -and $Server.Type -eq "tcp") { continue }
                    if ($trimmed -ne "") { $alpnValues += $trimmed }
                }
                if ($alpnValues.Count -gt 0) {
                    $tlsSettings["alpn"] = $alpnValues
                }
            }
            $streamSettings["tlsSettings"] = $tlsSettings
        }
        "reality" {
            $streamSettings["security"] = "reality"
            $streamSettings["realitySettings"] = @{
                serverName  = $Server.SNI
                fingerprint = $Server.Fingerprint
                publicKey   = $Server.PbkKey
                shortId     = $Server.Sid
                spiderX     = $Server.SpiderX
            }
        }
        default {
            $streamSettings["security"] = "none"
        }
    }

    # ── VLESS user ──
    $vlessUser = @{
        id         = $Server.UUID
        encryption = $Server.Encryption
        level      = 0
    }
    if ($Server.Flow -ne "" -and $Server.Flow -ne "none") {
        $vlessUser["flow"] = $Server.Flow
    }

    # ── Full config ──
    $config = @{
        log = @{
            loglevel = "info"
        }
        dns = @{
            servers = @(
                @{
                    address = "8.8.8.8"
                    domains = @("geosite:geolocation-!cn")
                },
                "1.1.1.1",
                "localhost"
            )
        }
        inbounds = @(
            @{
                tag      = "socks-in"
                port     = $LocalSocksPort
                listen   = "127.0.0.1"
                protocol = "socks"
                settings = @{
                    auth = "noauth"
                    udp  = $true
                }
                sniffing = @{
                    enabled      = $true
                    destOverride = @("http", "tls")
                }
            },
            @{
                tag      = "http-in"
                port     = $LocalHttpPort
                listen   = "127.0.0.1"
                protocol = "http"
                settings = @{}
                sniffing = @{
                    enabled      = $true
                    destOverride = @("http", "tls")
                }
            }
        )
        outbounds = @(
            @{
                tag      = "proxy"
                protocol = "vless"
                settings = @{
                    vnext = @(
                        @{
                            address = $Server.Address
                            port    = $Server.Port
                            users   = @($vlessUser)
                        }
                    )
                }
                streamSettings = $streamSettings
            },
            @{
                tag      = "direct"
                protocol = "freedom"
                settings = @{}
            },
            @{
                tag      = "block"
                protocol = "blackhole"
                settings = @{}
            }
        )
        routing = @{
            domainStrategy = "IPIfNonMatch"
            rules = @(
                @{
                    type        = "field"
                    ip          = @("geoip:private")
                    outboundTag = "direct"
                },
                @{
                    type        = "field"
                    domain      = @("geosite:category-ads-all")
                    outboundTag = "block"
                },
                @{
                    type        = "field"
                    port        = "0-65535"
                    outboundTag = "proxy"
                }
            )
        }
    }

    return $config | ConvertTo-Json -Depth 20
}

# ── Proxy Toggle ─────────────────────────────────────────────────────────────
function Enable-SystemProxy {
    param([int]$Port)
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $regPath -Name ProxyEnable  -Value 1
    Set-ItemProperty -Path $regPath -Name ProxyServer  -Value "127.0.0.1:$Port"
    # Bypass local addresses
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value "<local>;localhost;127.*;10.*;192.168.*"

    # Notify the system of proxy changes
    $signature = '[DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
    $wininet = Add-Type -MemberDefinition $signature -Name WinInet -Namespace OpenWave -PassThru -ErrorAction SilentlyContinue
    if ($wininet) {
        $wininet::InternetSetOption(0, 39, 0, 0) | Out-Null
        $wininet::InternetSetOption(0, 37, 0, 0) | Out-Null
    }
}

function Disable-SystemProxy {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0
    Remove-ItemProperty -Path $regPath -Name ProxyServer  -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $regPath -Name ProxyOverride -ErrorAction SilentlyContinue

    $signature = '[DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
    $wininet = Add-Type -MemberDefinition $signature -Name WinInet2 -Namespace OpenWave -PassThru -ErrorAction SilentlyContinue
    if ($wininet) {
        $wininet::InternetSetOption(0, 39, 0, 0) | Out-Null
        $wininet::InternetSetOption(0, 37, 0, 0) | Out-Null
    }
}

# ── Download & Extract Xray ─────────────────────────────────────────────────
function Install-Xray {
    if (Test-Path $XrayExe) {
        Write-Ok "Xray already installed at $XrayDir"
        return $true
    }

    Write-Step ">>>" "Downloading Xray v$XrayVersion..."

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $zipPath = "$InstallDir\xray.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $XrayZipUrl -OutFile $zipPath -UseBasicParsing
        $ProgressPreference = 'Continue'
    } catch {
        Write-Err "Failed to download Xray: $_"
        Write-C ""
        Write-C "  If GitHub is blocked, manually download xray-core and place it at:" -Color Yellow
        Write-C "  $XrayDir\xray.exe" -Color Yellow
        return $false
    }

    Write-Step ">>>" "Extracting..."
    try {
        # Remove old dir if exists
        if (Test-Path $XrayDir) { Remove-Item -Recurse -Force $XrayDir }
        Expand-Archive -Path $zipPath -DestinationPath $XrayDir -Force
        Remove-Item $zipPath -Force
    } catch {
        Write-Err "Failed to extract: $_"
        return $false
    }

    if (Test-Path $XrayExe) {
        Write-Ok "Xray installed successfully"
        return $true
    } else {
        Write-Err "xray.exe not found after extraction"
        return $false
    }
}

# ── Default Server ───────────────────────────────────────────────────────────
$DefaultVlessUri = "vless://a9bc195c-5835-4830-ab5e-a7bf8f577800@sg1.nlkx.shop:443/?encryption=none&flow=none&security=tls&sni=aka.ms&alpn=h3%2c+h2%2c+http%2f1.1&type=tcp&headerType=none#zoom-chalana"

# ── Get VLESS URI from user ─────────────────────────────────────────────────
function Get-VlessUri {
    if ($VlessUri) {
        return $VlessUri
    }

    # Check saved config
    $savedFile = "$InstallDir\servers.txt"
    $savedUris = @()
    if (Test-Path $savedFile) {
        $savedUris = @(Get-Content $savedFile | Where-Object { $_ -match '^vless://' })
    }

    Write-C ""
    Write-Separator
    Write-C "  SERVER CONFIGURATION" -Color Cyan
    Write-Separator
    Write-C ""

    # Build menu options
    $menuIndex = 0

    # Show default server
    $defaultParsed = Parse-VlessUri $DefaultVlessUri
    if ($defaultParsed) {
        Write-C "  Default server:" -Color Green
        Write-C "    [D] $($defaultParsed.Remark) ($($defaultParsed.Address):$($defaultParsed.Port))" -Color White
        Write-C ""
    }

    if ($savedUris.Count -gt 0) {
        Write-C "  Saved servers:" -Color Yellow
        for ($i = 0; $i -lt $savedUris.Count; $i++) {
            $parsed = Parse-VlessUri $savedUris[$i]
            if ($parsed) {
                $label = "$($parsed.Remark) ($($parsed.Address):$($parsed.Port))"
            } else {
                $maxLen = [Math]::Min(60, $savedUris[$i].Length)
                $label = $savedUris[$i].Substring(0, $maxLen) + "..."
            }
            Write-C "    [$($i+1)] $label" -Color White
        }
    }

    Write-C "    [N] Add a new server" -Color DarkGray
    Write-C ""
    $prompt = "  Select [D]efault"
    if ($savedUris.Count -gt 0) {
        $prompt += ", (1-$($savedUris.Count))"
    }
    $prompt += ", or [N]ew"
    $choice = Read-Host $prompt

    # Default server
    if ($choice -eq "" -or $choice.ToUpper() -eq "D") {
        Write-Ok "Using default server"
        return $DefaultVlessUri
    }

    # Saved server by number
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $savedUris.Count) {
        return $savedUris[[int]$choice - 1]
    }

    # New server
    Write-C ""
    Write-C "  Paste your VLESS URI below." -Color Yellow
    Write-C "  Format: vless://uuid@host:port?params#Name" -Color DarkGray
    Write-C ""
    $uri = Read-Host "  VLESS URI"

    if (-not $uri) {
        Write-Err "No URI provided. Exiting."
        return $null
    }

    # Save for next time
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $uri | Add-Content -Path $savedFile
    Write-Ok "Server saved for future use"

    return $uri
}

# ── Test Connection ──────────────────────────────────────────────────────────
function Test-ProxyConnection {
    param([int]$Port, [int]$Retries = 6)

    # First get our real IP (direct, no proxy)
    $realIp = $null
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
        $directResult = $wc.DownloadString("https://api.ipify.org")
        $realIp = $directResult.Trim()
        Write-Host "  [i] Your real IP: $realIp" -ForegroundColor DarkGray
    } catch {
        Write-Host "  [i] Could not determine real IP (network may be restricted)" -ForegroundColor DarkGray
    }

    for ($i = 1; $i -le $Retries; $i++) {
        Start-Sleep -Seconds 2
        try {
            $proxy = New-Object System.Net.WebProxy("http://127.0.0.1:$Port")
            $webClient = New-Object System.Net.WebClient
            $webClient.Proxy = $proxy
            $result = $webClient.DownloadString("https://api.ipify.org")
            $proxyIp = $result.Trim()

            if ($realIp -and $proxyIp -eq $realIp) {
                Write-Host "  ... Attempt $i/$Retries - proxy IP same as real IP, tunnel may not be routing..." -ForegroundColor Yellow
                continue
            }

            # Store proxy IP for display
            $script:DetectedProxyIp = $proxyIp
            return $true
        } catch {
            Write-Host "  ... Attempt $i/$Retries - waiting for tunnel..." -ForegroundColor DarkGray
        }
    }
    return $false
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

Clear-Host
Write-Host $Banner -ForegroundColor Cyan

# ── Step 1: Install Xray ──
Write-Separator
Write-C "  SETUP" -Color Cyan
Write-Separator
Write-C ""

if (-not (Install-Xray)) {
    Write-C ""
    Write-Err "Setup failed. Please check your internet connection."
    Read-Host "  Press Enter to exit"
    exit 1
}

# ── Step 2: Get server config ──
$uri = Get-VlessUri
if (-not $uri) { exit 1 }

$server = Parse-VlessUri $uri
if (-not $server) {
    Write-Err "Failed to parse VLESS URI. Check the format and try again."
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-C ""
Write-Ok "Server: $($server.Remark)"
Write-Ok "Address: $($server.Address):$($server.Port)"
Write-Ok "Transport: $($server.Type) | Security: $($server.Security)"

# ── Step 3: Generate config ──
Write-C ""
Write-Step ">>>" "Generating Xray config..."
$configJson = Generate-XrayConfig -Server $server
# Write UTF-8 without BOM (PS 5.1's -Encoding UTF8 adds BOM which Xray rejects)
[System.IO.File]::WriteAllText($ConfigPath, $configJson, (New-Object System.Text.UTF8Encoding $false))
Write-Ok "Config written to $ConfigPath"

# ── Step 4: Start Xray ──
Write-C ""
Write-Separator
Write-C "  CONNECTING" -Color Cyan
Write-Separator
Write-C ""
Write-Step ">>>" "Starting Xray tunnel..."

$xrayLogFile = "$InstallDir\xray-log.txt"
$xrayProcess = Start-Process -FilePath $XrayExe `
    -ArgumentList "run", "-config", $ConfigPath `
    -WindowStyle Hidden `
    -RedirectStandardOutput $xrayLogFile `
    -RedirectStandardError "$InstallDir\xray-err.txt" `
    -PassThru

if (-not $xrayProcess -or $xrayProcess.HasExited) {
    Write-Err "Failed to start Xray process"
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-Ok "Xray started (PID: $($xrayProcess.Id))"

try {
    # ── Step 5: Set system proxy ──
    Write-Step ">>>" "Setting system proxy -> 127.0.0.1:$LocalHttpPort"
    Enable-SystemProxy -Port $LocalHttpPort
    Write-Ok "System HTTP proxy enabled"

# ── Step 5b: Check for conflicting Chrome extensions ──
$extPathBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $extPathBase) {
    $manifests = Get-ChildItem -Path "$extPathBase\*\Extensions\*\*\manifest.json" -ErrorAction SilentlyContinue
    $blockingExts = @()
    foreach ($mFile in $manifests) {
        $manifest = Get-Content $mFile.FullName -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($manifest -and $manifest.permissions -contains "proxy") {
            $name = $manifest.name
            if ($name -match "__MSG_") { $name = "A VPN/Proxy Extension ($($mFile.Directory.Parent.Name))" }
            $blockingExts += $name
        }
    }
    $blockingExts = $blockingExts | Select-Object -Unique
    
    if ($blockingExts.Count -gt 0) {
        Write-C ""
        Write-C "  [!!] ACTION REQUIRED: Conflicting Chrome Extensions [!!]" -ForegroundColor Red
        Write-C "  The following extensions control your proxy and WILL block the tunnel:" -ForegroundColor Yellow
        foreach ($ext in $blockingExts) {
            Write-C "    - $ext" -ForegroundColor White
        }
        Write-C ""
        Write-C "  To fix this:" -ForegroundColor Cyan
        Write-C "  1. Open Chrome and go to: chrome://extensions" -ForegroundColor White
        Write-C "  2. Turn OFF the extensions listed above" -ForegroundColor White
        Write-C ""
        Read-Host "  Press Enter once you have disabled them to continue"
    }
}

# ── Step 6: Test connection ──
Write-C ""
Write-Step ">>>" "Testing connection..."
$connected = Test-ProxyConnection -Port $LocalHttpPort

if ($connected) {
    $ipLine = if ($script:DetectedProxyIp) { "    Tunnel IP   -> $($script:DetectedProxyIp)" } else { "" }
    Write-C ""
    Write-C "  ============================================================" -ForegroundColor Green
    Write-C "                                                              " -ForegroundColor Green
    Write-C "    CONNECTED - You're bypassing restrictions now!            " -ForegroundColor Green
    Write-C "                                                              " -ForegroundColor Green
    if ($ipLine) { Write-C "$ipLine" -ForegroundColor Green }
    Write-C "    HTTP Proxy  -> 127.0.0.1:$LocalHttpPort                          " -ForegroundColor Green
    Write-C "    SOCKS Proxy -> 127.0.0.1:$LocalSocksPort                          " -ForegroundColor Green
    Write-C "                                                              " -ForegroundColor Green
    Write-C "  ============================================================" -ForegroundColor Green
} else {
    Write-C ""
    Write-C "  WARNING: Tunnel started but the IP did not change." -ForegroundColor Yellow
    Write-C "  The VLESS server may be misconfigured or unreachable." -ForegroundColor Yellow
    Write-C "  Check Xray logs at: $InstallDir\xray-log.txt" -ForegroundColor Yellow
    Write-C "  Proxy is set - you can try browsing manually." -ForegroundColor Yellow
}

Write-C ""
Write-Separator
Write-C "  Press Enter to disconnect and restore settings." -Color DarkGray
Write-Separator
Write-C ""

    # ── Wait for user to disconnect ──
    try {
        Read-Host "  Waiting... press Enter to disconnect"
    } catch {
        # Ctrl+C caught
    }
} finally {
    # ── Cleanup ──
    Write-C ""
    Write-Step ">>>" "Cleaning up..."

    try { Stop-Process -Id $xrayProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
    Write-Ok "Xray process stopped"

    Disable-SystemProxy
    Write-Ok "System proxy restored"

    Write-C ""
    Write-C "  ============================================================" -ForegroundColor Yellow
    Write-C "    DISCONNECTED - Original settings restored.                " -ForegroundColor Yellow
    Write-C "  ============================================================" -ForegroundColor Yellow
    Write-C ""
}
