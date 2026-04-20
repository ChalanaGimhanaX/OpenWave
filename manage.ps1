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

function Parse-VlessUri {
    param([string]$Uri)
    if (-not $Uri.StartsWith("vless://")) { return $null }
    $stripped = $Uri.Substring(8)

    $hashIdx = $stripped.LastIndexOf('#')
    if ($hashIdx -ge 0) {
        $main   = $stripped.Substring(0, $hashIdx)
        $remark = [System.Uri]::UnescapeDataString($stripped.Substring($hashIdx + 1))
    } else {
        $main   = $stripped
        $remark = "Unnamed"
    }

    $atIdx = $main.IndexOf('@')
    if ($atIdx -lt 0) { return $null }
    $rest = $main.Substring($atIdx + 1)

    $qIdx = $rest.IndexOf('?')
    if ($qIdx -ge 0) {
        $hostPort = $rest.Substring(0, $qIdx)
        $queryStr = $rest.Substring($qIdx + 1)
    } else {
        $hostPort = $rest
        $queryStr = ""
    }
    $hostPort = $hostPort.TrimEnd('/')

    $addr = $null
    $port = "443"
    if ($hostPort -match '^(.+):(\d+)$') {
        $addr = $Matches[1]
        $port = $Matches[2]
    } else {
        return $null
    }

    $sec  = "none"
    $typ  = "tcp"
    if ($queryStr -ne "") {
        $pairs = $queryStr.Split('&')
        foreach ($pair in $pairs) {
            $eqIdx = $pair.IndexOf('=')
            if ($eqIdx -gt 0) {
                $k = $pair.Substring(0, $eqIdx)
                $v = $pair.Substring($eqIdx + 1)
                if ($k -eq 'security') { $sec = $v }
                if ($k -eq 'type')     { $typ = $v }
            }
        }
    }

    return @{ Remark=$remark; Address=$addr; Port=$port; Security=$sec; Type=$typ }
}

function Show-Servers {
    if (-not (Test-Path $SavedFile)) {
        Write-C "  No servers saved yet." -C Yellow
        return @()
    }
    $uris = @(Get-Content $SavedFile | Where-Object { $_ -match '^vless://' })
    if ($uris.Count -eq 0) {
        Write-C "  No servers saved yet." -C Yellow
        return @()
    }
    Write-C ""
    Write-C "  +------+---------------------------+-------------------+------+" -C DarkCyan
    Write-C "  |  #   | Name                      | Address           | Sec  |" -C DarkCyan
    Write-C "  +------+---------------------------+-------------------+------+" -C DarkCyan
    for ($i = 0; $i -lt $uris.Count; $i++) {
        $s = Parse-VlessUri $uris[$i]
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
    Write-C "  Paste your VLESS URI:" -C Yellow
    $uri = Read-Host "  "
    if (-not $uri.StartsWith("vless://")) {
        Write-C "  [!!] Invalid VLESS URI" -C Red
        return
    }
    $s = Parse-VlessUri $uri
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
