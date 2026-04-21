<#
.SYNOPSIS
    OpenWave Server Manager - Add, remove, and list saved VLESS servers.
.DESCRIPTION
    Run:  .\manage.ps1
    or:   irm https://your-host.com/manage.ps1 | iex
#>

$InstallDir = "$env:USERPROFILE\.openwave"
$SavedFile  = "$InstallDir\servers.txt"

function Write-C { param([string]$T, [string]$C = "White"); Write-Host $T -ForegroundColor $C }

$Banner = @"

   ============================================
     OpenWave - Server Manager
   ============================================

"@

function Parse-ProxyUri {
    param([string]$Uri)
    if ($Uri.StartsWith("vmess://")) {
        $b64 = $Uri.Substring(8); $p = $b64.Length % 4
        if ($p -ne 0) { $b64 += "=" * (4 - $p) }
        try {
            $v = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
            return @{ Protocol="vmess"; Remark=if($v.ps){$v.ps}else{"VMESS"}; Address=$v.add; Port=$v.port; Security=if($v.tls){$v.tls}else{"none"}; Type=if($v.net){$v.net}else{"tcp"} }
        } catch { return $null }
    }
    
    $prot = if ($Uri.StartsWith("vless://")) { "vless" } elseif ($Uri.StartsWith("trojan://")) { "trojan" } else { return $null }
    $s = $Uri.Substring($prot.Length + 3)
    $h = $s.LastIndexOf('#'); $rmk = if ($h -ge 0) { [Uri]::UnescapeDataString($s.Substring($h + 1)) } else { "Unnamed" }
    $m = if ($h -ge 0) { $s.Substring(0, $h) } else { $s }
    $at = $m.IndexOf('@'); if ($at -lt 0) { return $null }
    $r = $m.Substring($at + 1)
    $q = $r.IndexOf('?'); $hp = if ($q -ge 0) { $r.Substring(0, $q) } else { $r }; $qs = if ($q -ge 0) { $r.Substring($q + 1) } else { "" }
    $hp = $hp.TrimEnd('/')
    if ($hp -match '^\[(.+)\]:(\d+)$' -or $hp -match '^(.+):(\d+)$') { $ad = $Matches[1]; $pt = $Matches[2] } else { return $null }
    $sec="none"; $typ="tcp"
    if ($qs -ne "") {
        foreach ($pair in $qs.Split('&')) {
            $e = $pair.IndexOf('=')
            if ($e -gt 0) { $k=$pair.Substring(0,$e); $v=$pair.Substring($e+1); if($k -eq 'security'){$sec=$v}; if($k -eq 'type'){$typ=$v} }
        }
    }
    return @{ Protocol=$prot; Remark=$rmk; Address=$ad; Port=$pt; Security=$sec; Type=$typ }
}

function Show-Servers {
    if (-not (Test-Path $SavedFile)) {
        Write-C "  No servers saved yet." -C Yellow
        return @()
    }
        $uris = @(Get-Content $SavedFile | Where-Object { $_ -match '^(vless|vmess|trojan)://' })
    if ($uris.Count -eq 0) {
        Write-C "  No servers saved yet." -C Yellow
        return @()
    }
    Write-C ""
    Write-C "  +------+---------------------------+-------------------+------+" -C DarkCyan
    Write-C "  |  #   | Name                      | Address           | Sec  |" -C DarkCyan
    Write-C "  +------+---------------------------+-------------------+------+" -C DarkCyan
    for ($i = 0; $i -lt $uris.Count; $i++) {
        $s = Parse-ProxyUri $uris[$i]
        if ($s) {
            $name  = $s.Remark.PadRight(25).Substring(0,25)
            $adr   = ("$($s.Address):$($s.Port)").PadRight(17).Substring(0,17)
            $sec   = $s.Security.PadRight(4).Substring(0,4)
            Write-C "  |  $($i+1)   | $name | $adr | $sec |" -C White
        }
    }
    Write-C "  +------+---------------------------+-------------------+------+" -C DarkCyan
    Write-C ""
    return $uris
}

function Add-Server {
    Write-C ""
    Write-C "  Paste your Proxy URI (vless/vmess/trojan):" -C Yellow
    $uri = Read-Host "  "
    if (-not ($uri.StartsWith("vless://") -or $uri.StartsWith("vmess://") -or $uri.StartsWith("trojan://"))) {
        Write-C "  [!!] Invalid Proxy URI" -C Red
        return
    }
    $s = Parse-ProxyUri $uri
    if (-not $s) {
        Write-C "  [!!] Failed to parse URI" -C Red
        return
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $uri | Add-Content -Path $SavedFile
    Write-C "  [OK] Added: $($s.Remark) ($($s.Address):$($s.Port))" -C Green
}

function Remove-Server {
    $uris = Show-Servers
    if ($uris.Count -eq 0) { return }
    $idx = Read-Host "  Enter server # to remove"
    if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $uris.Count) {
        $list = [System.Collections.ArrayList]@($uris)
        $list.RemoveAt([int]$idx - 1)
        if ($list.Count -gt 0) {
            $list | Set-Content -Path $SavedFile
        } else {
            Remove-Item -Path $SavedFile -Force
        }
        Write-C "  [OK] Server removed" -C Green
    } else {
        Write-C "  [!!] Invalid selection" -C Red
    }
}

function Uninstall-OpenWave {
    Write-C ""
    Write-C "  This will remove V2Ray binary and all saved configs." -C Yellow
    $confirm = Read-Host "  Type 'yes' to confirm"
    if ($confirm -eq 'yes') {
        if (Test-Path $InstallDir) {
            Remove-Item -Recurse -Force $InstallDir
            Write-C "  [OK] OpenWave uninstalled from $InstallDir" -C Green
        }
    } else {
        Write-C "  Cancelled." -C DarkGray
    }
}

# ── Main Loop ──
Clear-Host
Write-Host $Banner -ForegroundColor Cyan

while ($true) {
    Write-C ""
    Write-C "  [1] List servers" -C White
    Write-C "  [2] Add server" -C White
    Write-C "  [3] Remove server" -C White
    Write-C "  [4] Connect (runs connect.ps1)" -C White
    Write-C "  [5] Uninstall OpenWave" -C DarkGray
    Write-C "  [Q] Quit" -C DarkGray
    Write-C ""
    $choice = Read-Host "  Choice"

    switch ($choice.ToUpper()) {
        "1" { Show-Servers }
        "2" { Add-Server }
        "3" { Remove-Server }
        "4" {
            $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
            if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
            $connectScript = Join-Path $scriptDir "connect.ps1"
            if (Test-Path $connectScript) {
                & $connectScript
            } else {
                Write-C "  connect.ps1 not found in $scriptDir" -C Red
            }
        }
        "5" { Uninstall-OpenWave }
        "Q" { Write-C "  Bye!" -C Cyan; exit 0 }
        default { Write-C "  Invalid choice" -C Red }
    }
}
