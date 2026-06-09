# ============================================================
# SCRIPT  : PS-MRTG — Network Bandwidth Monitor
# VERSION : 1.22
# AUTEUR  : Eric Guiffault
# DATE    : 2026-05
#
# DESCRIPTION :
#   Real-time network bandwidth monitoring.
#   Classic MRTG style - 4 aggregated time views.
#   Interactive HTML interface - 100% offline.
#   Compatible with strict ConstrainedLanguage (PS 5.1 + PS 7+).
#
# CHANGELOG v1.22 :
#   - FIX auto-stop: the window is now detected via ANY browser process
#     using our dedicated --user-data-dir profile, instead of the single
#     spawned PID. Edge/Chrome hand off the launched process to an
#     existing instance, which made the PID-based watch never fire and
#     left the hidden PowerShell running forever. Closing the dashboard
#     window now reliably stops the script.
#   - Single instance: on startup any previous PS-MRTG instance (and its
#     orphaned browser) is stopped via a lock file, so two runs no longer
#     overlap and double the graphs.
#   - Clean exit: lock released and our browser window closed on stop.
#   - Requires WMI/CIM (Win32_Process) for the profile-based watch;
#     falls back to the spawned handle if CIM is unavailable.
#
# CHANGELOG v1.21 :
#   - PowerShell Gallery metadata for discoverability: icon (ICONURI),
#     expanded TAGS (+ PSEdition_Desktop/Core compatibility badges),
#     richer keyword-front-loaded DESCRIPTION, ASCII copyright.
#   - No functional change to monitoring.
#
# CHANGELOG v1.20 :
#   - FIX (regression v1.18): in hidden mode the browser-watch could
#     stop the script within ~5s when the launched browser process
#     handed off / exited immediately, freezing the data (empty graph).
#     Auto-stop is now hardened: 30s grace period, only triggers after
#     the process was confirmed alive AND exited on 2 consecutive checks;
#     if the process is never seen alive, auto-stop disables itself and
#     data keeps flowing.
#   - Diagnostic log (%TEMP%\PSMrtg\PS-MRTG.log) via Start-Transcript:
#     records everything the (possibly hidden) instance does, so silent
#     failures are now visible after the fact.
#
# CHANGELOG v1.19 :
#   - All comments, console messages and HTML UI translated to English.
#     Side effect: no more accented characters -> no encoding/mojibake risk.
#   - ISE: a "Please wait a few seconds while the monitor window loads..."
#     message is now shown before the relaunch, so the delay is explicit.
#
# CHANGELOG v1.18 :
#   - Hidden PowerShell window (HideConsole): the script relaunches
#     in a hidden-window powershell.exe (-Hidden). Only the
#     browser window stays visible.
#   - Auto-stop: browser opened in --app mode (dedicated,
#     monitorable process). On closing the HTML window, the loop
#     detects HasExited and stops -> no PowerShell window
#     lingering on the system.
#   - ISE: hidden relaunch too when HideConsole is active.
#
# CHANGELOG v1.17 :
#   - ISE detection fixed: uses $PSCommandPath first, so the
#     script also works when run directly or installed from the
#     PowerShell Gallery (not only when open+saved in the ISE).
#     ISE fallback kept for a saved (non-Untitled) file.
#
# CHANGELOG v1.16 :
#   - X axis split into 6 EQUAL segments (7 ticks) on all
#     charts. Step = window / 6: 10 min (Live 1h), 1 h (6h),
#     10 h (2.5d), 60 h (15d). Regular, aligned ticks.
#
# CHANGELOG v1.15 :
#   - Time X axis with FIXED domain: data is drawn at its
#     real position. A partial history only occupies its fraction
#     of width (e.g. 1 day of data on the 15d view = 1/15 of the chart)
#     instead of being stretched across the whole width.
#   - Tooltip: full date + time (DD/MM HH:MM:SS).
#
# CHANGELOG v1.14 :
#   - Each chart shows its PERIOD (look-back) next to its type:
#     Live (5s) · 1h / 6h (30s) / 2.5j (5min) / 15j (30min).
#   - Fix: the "Recent" view covers 6h (not 1h as displayed).
#   - Hover tooltip: full explanation of each view's look-back.
#
# CHANGELOG v1.13 :
#   - X axis (multi-day views): date + time on a SINGLE line
#     in "DD/MM HH:MM" format. Spaced ticks -> no
#     chevauchement.
#
# CHANGELOG v1.12 :
#   - X axis: multi-day views (2.5d / 15d) show the DATE (DD/MM)
#     on a 2nd line below the time -> date + time visible without
#     overlap. Spaced ticks for maximum readability.
#
# CHANGELOG v1.11 :
#   - X axis (hours) enlarged to the same size as the Y axis (rates)
#     -> time labels much more readable.
#
# CHANGELOG v1.10 :
#   - Y scale: finer automatic steps (1-2-5 progression),
#     notably 200 and 500 Mbps, to avoid 100M -> 1G jumps.
#   - Same steps offered in fixed scale (dropdown).
#   - The scale always adjusts to the alarm threshold (auto).
#   - Alarm threshold DISABLED by default (enable on demand).
#
# CHANGELOG v1.9 :
#   - "All" view: the 4 charts now share the SAME
#     Y scale (same height in Mbps) -> reliable comparison.
#   - The alarm threshold PUSHES the scale (auto mode): the red line
#     is always visible and appears simultaneously on all 4 charts.
#   - More readable Y axis: larger font + unit (Kbps/Mbps/Gbps)
#     shown on a 2nd line below the value.
#   - The full-screen view keeps its own scale (fine reading),
#     but also includes the threshold so it stays visible.
#
# ARCHITECTURE :
#   PS collects network counters every 5s
#   PS writes network_data.js every 2s
#   The browser reloads network_data.js every 2s
#   Chart.js draws the IN/OUT charts
#
# TIME VIEWS (look-back = covered window, full buffer = 720 points):
#   Live  : 1 pt / 5s    -> 720 x 5s    = 3 600 s   = 1 h
#   Hour  : 1 pt / 30s   -> 720 x 30s   = 21 600 s  = 6 h   (avg. 6 raw pts)
#   Day   : 1 pt / 5min  -> 720 x 5min  = 3 600 min = 60 h = 2.5 d (avg. 60 pts)
#   Week  : 1 pt / 30min -> 720 x 30min = 21 600 min = 360 h = 15 d (avg. 360 pts)
#
# INSTALLATION OFFLINE — Chart.js :
#   Download: chart.js@4.4.0/dist/chart.umd.min.js
#   Copy to: %USERPROFILE%\Documents\chartjs.min.js
#             or: %TEMP%\PSMrtg\chartjs.min.js
#
# BROWSER: Edge or Chrome recommended
# ============================================================

param([switch]$Hidden)

# ============================================================
# --- Hidden console (no PowerShell window) - v1.18+ ---
# ============================================================
# $true  : the script relaunches itself in a HIDDEN PowerShell; only the
#          browser window stays visible. When it is closed, the
#          main loop detects the end of the browser process and
#          stops - no PowerShell window is left lingering on the system.
# $false : keeps the console (useful for diagnostics).
# Without a console, Ctrl+C is no longer possible: auto-stop on closing
# the HTML window takes over.
$HideConsole = $true

# Hidden relaunch (outside ISE): if requested and we are not already
# the hidden instance, relaunch in a hidden-window powershell.exe,
# then exit the visible instance. The -Hidden switch prevents any
# relaunch loop.
if ($HideConsole -and -not $Hidden -and $Host.Name -ne "Windows PowerShell ISE Host") {
    $self = $PSCommandPath
    if ($self -and (Test-Path -Path $self -PathType Leaf)) {
        Start-Process -FilePath "powershell.exe" `
                      -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$self`"","-Hidden" `
                      -WindowStyle Hidden
        return
    }
    # Path not found (e.g. code pasted in console): continue visible.
}

# -- ISE detection: relaunch in powershell.exe ---------------
# The ISE handles continuous monitoring poorly: switch to powershell.exe,
# hidden if $HideConsole else visible. Reliable path via $PSCommandPath
# (also set when the script is installed from the PowerShell Gallery).
if ($Host.Name -eq "Windows PowerShell ISE Host") {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath -and $psISE -and $psISE.CurrentFile -and -not $psISE.CurrentFile.IsUntitled) {
        $scriptPath = $psISE.CurrentFile.FullPath
    }
    if ($scriptPath -and (Test-Path -Path $scriptPath -PathType Leaf)) {
        if ($HideConsole) {
            Write-Host "  ISE detected - launching in a hidden powershell.exe..." -ForegroundColor Cyan
            Write-Host "  Please wait a few seconds while the monitor window loads..." -ForegroundColor Yellow
            Start-Process -FilePath "powershell.exe" `
                          -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$scriptPath`"","-Hidden" `
                          -WindowStyle Hidden
        } else {
            Write-Host "  ISE detected - launching in powershell.exe..." -ForegroundColor Cyan
            Write-Host "  Please wait a few seconds while the monitor window loads..." -ForegroundColor Yellow
            Start-Process -FilePath "powershell.exe" `
                          -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass",
                                        "-NoExit","-File","`"$scriptPath`"" `
                          -WindowStyle Normal
        }
    } else {
        Write-Host "  Save the script (Ctrl+S) then relaunch." -ForegroundColor Red
    }
    return
}

# ============================================================
# SECTION 1 — CONFIGURATION UTILISATEUR
# All editable settings are here
# ============================================================

# Alarm threshold value in Mbps (red line on the chart)
# Pre-filled value, used when the threshold is enabled.
$ThresholdAlertMbps = 150

# Threshold enabled at startup: $true = visible, $false = hidden
# v1.10 : disabled by default (the user enables it on demand)
$ThresholdEnabled   = $false

# Echelle Y :
#   "auto"  = paliers automatiques (progression fine 1-2-5 :
#             ...100M -> 200M -> 500M -> 1G -> 2G -> 5G -> 10G...)
#   number  = fixed value in Mbps (e.g. 1000 to lock at 1 Gbps)
$YScaleMode = "auto"

# Maximum number of points kept per time view
$MaxPoints   = 720

# Network counter collection interval (seconds)
$IntervalSec = 5

# network_data.js write frequency (seconds)
$WriteEvery  = 2

# ============================================================
# SECTION 2 — CHEMINS DE FICHIERS
# ============================================================

# Dossier de travail temporaire
$scriptTemp = "$env:TEMP\PSMrtg"
if (-not (Test-Path $scriptTemp)) {
    New-Item -ItemType Directory -Path $scriptTemp -Force | Out-Null
}

# --- Diagnostic log (essential in hidden mode) ----------------- v1.20
# In hidden mode there is no visible console, so a silent failure looks
# like "nothing happens". This transcript records everything the working
# instance does (interface detection, browser launch, per-2s bandwidth
# log, and any error or auto-stop) into a file you can open afterwards:
#   %TEMP%\PSMrtg\PS-MRTG.log
Start-Transcript -Path "$scriptTemp\PS-MRTG.log" -Force -ErrorAction SilentlyContinue | Out-Null

# Dashboard HTML file (opened in the browser)
$htmlFile = "$scriptTemp\dashboard.html"

# JS data file (reloaded every 2s by the browser)
$dataFile = "$scriptTemp\network_data.js"

# Browser -> PS command file (threshold, yScale, etc.)
$cmdFile  = "$scriptTemp\mrtg_cmd.js"

# Dedicated browser profile (--app mode): isolates the Edge/Chrome instance and
# creates a CLEAN, monitorable process, for auto-stop on closing
# the window. Unique per run (PID) -> no stale cache reuse.
$profileDir = "$scriptTemp\browser_profile_$PID"
Remove-Item -Path "$scriptTemp\browser_profile_*" -Recurse -Force -ErrorAction SilentlyContinue

# --- Single instance (v1.22) --------------------------------------
# Two overlapping runs would both write network_data.js and the graphs
# would "double up". On startup we stop any previous PS-MRTG instance
# (recorded in a lock file) and its orphaned browser, then claim the lock.
$lockFile = "$scriptTemp\instance.lock"
if (Test-Path $lockFile) {
    try {
        $old        = (Get-Content -Path $lockFile -ErrorAction Stop) -split '\|'
        $oldPid     = [int]$old[0]
        $oldProfile = if ($old.Count -gt 1) { $old[1] } else { "" }
        if ($oldPid -and $oldPid -ne $PID) {
            $op = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($op -and ($op.ProcessName -eq 'powershell' -or $op.ProcessName -eq 'pwsh')) {
                Write-Host "  Stopping previous PS-MRTG instance (PID $oldPid)..." -ForegroundColor Yellow
                Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
            }
        }
        # Kill the previous run's orphaned browser (matched by its profile dir)
        if ($oldProfile) {
            try {
                Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction Stop |
                    Where-Object { $_.CommandLine -like "*$oldProfile*" } |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
    } catch { }
}
# Claim the lock for this instance (PID + our profile dir)
"$PID|$profileDir" | Set-Content -Path $lockFile -Encoding ASCII -ErrorAction SilentlyContinue

# ============================================================
# SECTION 3 - GLOBAL SCRIPT VARIABLES
# ============================================================

$script:startTime        = Get-Date           # Start time
$script:ThresholdAlert   = $ThresholdAlertMbps
$script:ThresholdEnabled = $ThresholdEnabled
$script:YScaleMode       = $YScaleMode

# Hashtable of data buffers per interface
# Key = interface name, Value = @{LiveTs; LiveIn; LiveOut; ...}
$script:interfaces   = @{}

# Hashtable of the last raw counters per interface
# Key = interface name, Value = @{LastIn; LastOut; LastTs}
$script:rawCounters  = @{}

# Hashtable of interface metadata (description, speed, etc.)
$script:ActiveIfaces = @{}

# Flag to avoid repeated warning messages
$script:debugDone    = $false

# ============================================================
# SECTION 4 — FONCTIONS UTILITAIRES
# Compatible ConstrainedLanguage strict (pas de [math]::)
# ============================================================

# Returns the Unix timestamp in milliseconds (long integer)
function Get-NowMs {
    $epoch = [datetime]"1970-01-01 00:00:00"
    $span  = (Get-Date).ToUniversalTime() - $epoch
    return [long]$span.TotalMilliseconds
}

# Returns the number of seconds elapsed since start
function Get-ElapsedSec {
    return [int]((Get-Date) - $script:startTime).TotalSeconds
}

# Rounds a double to $dec decimals
# CRITICAL: do NOT use .ToString("Fx") - the FR locale
#    produces "0,496" instead of "0.496" -> conversion [double] = 496 !
#    Solution: pure arithmetic, locale-immune
function Round-Double {
    param([double]$n, [int]$dec)
    if ($dec -le 0) { return [double]([int]$n) }
    # Compute the 10^dec factor without [math]::Pow (forbidden in CL)
    $f = [double]1
    $m = $dec
    while ($m -gt 0) { $f = $f * 10.0; $m-- }
    # Integer rounding then re-division -> clean result
    $rounded = [int]($n * $f + 0.5)
    return [double]$rounded / $f
}

# Formats an Mbps value into a readable string (Kbps / Mbps / Gbps)
function Format-Mbps {
    param([double]$mbps)
    if ($mbps -ge 1000) { return "$(Round-Double ($mbps/1000) 2) Gbps" }
    if ($mbps -ge 1)    { return "$(Round-Double $mbps 2) Mbps" }
    return "$([int]($mbps * 1000)) Kbps"
}

# Converts a double to a JSON string with explicit decimal point
# CRITICAL: prevents PowerShell from producing "0,496" (FR locale)
#    in the .js file, which would break the JSON on the browser side
function Double-ToJs {
    param([double]$v)
    $intPart  = [int]$v
    $fracPart = $v - [int]$v
    if ($fracPart -lt 0) { $fracPart = -$fracPart }
    # 6 decimals are enough for values in Mbps
    $fracInt = [int]($fracPart * 1000000 + 0.5)
    $fracStr = "$fracInt"
    # Zero-padding to 6 digits
    while ($fracStr.Length -lt 6) { $fracStr = "0$fracStr" }
    # Strip trailing zeros
    $fracStr = $fracStr.TrimEnd('0')
    if ($fracStr.Length -eq 0) { return "$intPart" }
    return "$intPart.$fracStr"
}

# ============================================================
# SECTION 5 - LINK SPEED DETECTION
# 3 cascading methods to maximize compatibility
# ============================================================
function Get-LinkSpeed {
    param([string]$IfaceName)

    # Method 1: WMI Win32_NetworkAdapter (reliable on PS 5.1)
    try {
        $wql = "NetConnectionID='$($IfaceName -replace "'","''")'"
        $w   = Get-WmiObject -Class Win32_NetworkAdapter -Filter $wql -ErrorAction Stop
        if ($null -ne $w) {
            $spd = [long]0
            try { $spd = [long]$w.Speed } catch {}
            if ($spd -gt 0) { return $spd }
        }
    } catch {}

    # Method 2: Get-NetAdapter (may fail under ConstrainedLanguage)
    try {
        foreach ($a in (Get-NetAdapter -ErrorAction Stop)) {
            if ($a.Name -eq $IfaceName) {
                $spd = [long]0
                try { $spd = [long]$a.LinkSpeed } catch {}
                if ($spd -gt 0) { return $spd }
                # Some drivers expose the speed as a string "1 Gbps"
                try {
                    $ls = "$($a.LinkSpeed)"
                    if ($ls -match '(\d+)') {
                        $v = [long]$Matches[1]
                        if ($v -gt 0) { return $v }
                    }
                } catch {}
            }
        }
    } catch {}

    return [long]0
}

# ============================================================
# SECTION 6 - ACTIVE NETWORK INTERFACE DETECTION
# ============================================================
function Get-ActiveInterfaces {
    $result = @{}

    # Method 1: Get-NetAdapter (interfaces with Status=Up)
    try {
        foreach ($a in (Get-NetAdapter -ErrorAction Stop)) {
            if ("$($a.Status)" -ne "Up") { continue }
            $name = "$($a.Name)"
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $ifIndex   = [int]0
            try { $ifIndex = [int]$a.InterfaceIndex } catch {}

            $linkSpeed = Get-LinkSpeed -IfaceName $name
            $descr     = ""; try { $descr = "$($a.InterfaceDescription)" } catch {}
            $mac       = ""; try { $mac   = "$($a.MacAddress)"           } catch {}

            $result[$name] = @{
                Name          = $name
                Description   = $descr
                LinkSpeedBps  = $linkSpeed
                LinkSpeedMbps = [double]($linkSpeed / 1000000)
                MacAddress    = $mac
                IfIndex       = $ifIndex
            }
            Write-Host "  [OK] '$name' | $(Format-Mbps ([double]($linkSpeed/1000000))) | $descr" `
                       -ForegroundColor Green
        }
    } catch {
        Write-Host "  Get-NetAdapter echec : $_" -ForegroundColor Yellow
    }

    # Method 2 fallback: WMI Win32_NetworkAdapter
    if ($result.Count -eq 0) {
        Write-Host "  Fallback WMI Win32_NetworkAdapter..." -ForegroundColor Yellow
        try {
            foreach ($w in (Get-WmiObject -Class Win32_NetworkAdapter `
                            -Filter "NetEnabled=True" -ErrorAction Stop)) {
                $name = "$($w.NetConnectionID)"
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "$($w.Name)" }
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                $speed    = [long]0; try { $speed = [long]$w.Speed    } catch {}
                $idx      = [int]0;  try { $idx   = [int]$w.InterfaceIndex } catch {}
                $descr    = "";      try { $descr = "$($w.Description)" } catch {}

                $result[$name] = @{
                    Name          = $name
                    Description   = $descr
                    LinkSpeedBps  = $speed
                    LinkSpeedMbps = [double]($speed / 1000000)
                    MacAddress    = "$($w.MACAddress)"
                    IfIndex       = $idx
                }
                Write-Host "  [WMI] '$name' | $descr" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "  WMI Win32_NetworkAdapter echec : $_" -ForegroundColor Red
        }
    }

    return $result
}

# ============================================================
# SECTION 7 - READING NETWORK COUNTERS
# 3 cascading methods to maximize compatibility
# ============================================================
function Get-NetworkCounters {
    $result = @{}

    # Method 1: Get-NetAdapterStatistics (most reliable, PS 4+)
    try {
        $ok = $false
        foreach ($s in (Get-NetAdapterStatistics -ErrorAction Stop)) {
            if ($null -eq $s) { continue }
            $name = "$($s.Name)"
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $bIn  = [long]0; try { $bIn  = [long]$s.ReceivedBytes } catch {}
            $bOut = [long]0; try { $bOut = [long]$s.SentBytes      } catch {}
            $result[$name] = @{ BytesIn=$bIn; BytesOut=$bOut; Method="GNS" }
            $ok = $true
        }
        if ($ok) { return $result }
    } catch {
        Write-Host "  Get-NetAdapterStatistics echec : $_" -ForegroundColor Yellow
    }

    # Method 2: WMI Win32_PerfRawData_Tcpip_NetworkInterface
    try {
        $ok = $false
        foreach ($p in (Get-WmiObject -Class Win32_PerfRawData_Tcpip_NetworkInterface `
                        -ErrorAction Stop)) {
            if ($null -eq $p) { continue }
            $name = "$($p.Name)"
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $bIn  = [long]0; try { $bIn  = [long]$p.BytesReceivedPersec } catch {}
            $bOut = [long]0; try { $bOut = [long]$p.BytesSentPersec      } catch {}
            $result[$name] = @{ BytesIn=$bIn; BytesOut=$bOut; Method="WMI_PERF" }
            $ok = $true
        }
        if ($ok) { return $result }
    } catch {
        Write-Host "  WMI PerfRawData echec : $_" -ForegroundColor Yellow
    }

    # Method 3: Get-Counter (EN only for compatibility)
    try {
        $sIn  = Get-Counter -Counter "\Network Interface(*)\Bytes Received/sec" `
                -ErrorAction Stop
        $sOut = Get-Counter -Counter "\Network Interface(*)\Bytes Sent/sec" `
                -ErrorAction Stop
        foreach ($cs in $sIn.CounterSamples) {
            $iName = "$($cs.InstanceName)"
            if (-not $result.ContainsKey($iName)) {
                $result[$iName] = @{ BytesIn=[long]0; BytesOut=[long]0; Method="CTR" }
            }
            try { $result[$iName].BytesIn  = [long]$cs.CookedValue } catch {}
        }
        foreach ($cs in $sOut.CounterSamples) {
            $iName = "$($cs.InstanceName)"
            if (-not $result.ContainsKey($iName)) {
                $result[$iName] = @{ BytesIn=[long]0; BytesOut=[long]0; Method="CTR" }
            }
            try { $result[$iName].BytesOut = [long]$cs.CookedValue } catch {}
        }
        if ($result.Count -gt 0) { return $result }
    } catch {}

    Write-Host "  WARN : No counter method available !" -ForegroundColor Red
    return $result
}

# ============================================================
# SECTION 8 - MATCH INTERFACE NAME <-> COUNTER KEY
# The interface name (Get-NetAdapter) may differ from the
# counter name (WMI encodes spaces and # differently)
# 5 cascading strategies
# ============================================================
function Find-CounterKey {
    param(
        [string]$IfaceName,   # Nom Get-NetAdapter (ex: "Wi-Fi")
        [string]$IfaceDesc,   # Description (ex: "Intel Wi-Fi 6E")
        [hashtable]$Counters  # Result of Get-NetworkCounters
    )
    if ($Counters.Count -eq 0) { return $null }

    # S1 : correspondance exacte (cas nominal)
    foreach ($k in $Counters.Keys) {
        if ($k -eq $IfaceName) { return $k }
    }

    # S2: case-insensitive
    $nLow = $IfaceName.ToLower()
    foreach ($k in $Counters.Keys) {
        if ($k.ToLower() -eq $nLow) { return $k }
    }

    # S3 : contains bidirectionnel
    foreach ($k in $Counters.Keys) {
        $kl = $k.ToLower()
        if ($kl.Contains($nLow))                          { return $k }
        if ($nLow.Contains($kl) -and $kl.Length -gt 3)   { return $k }
    }

    # S4: WMI encoding (spaces -> _, # -> _, special chars -> _)
    $wmiEnc = $IfaceName.ToLower() -replace '[^a-z0-9]','_'
    foreach ($k in $Counters.Keys) {
        if (($k.ToLower() -replace '[^a-z0-9]','_') -eq $wmiEnc) { return $k }
    }

    # S5: match on the first 8 alphanumeric chars of the description
    if (-not [string]::IsNullOrEmpty($IfaceDesc)) {
        $dClean = $IfaceDesc.ToLower() -replace '[^a-z0-9]',''
        $dShort = if ($dClean.Length -gt 8) { $dClean.Substring(0,8) } else { $dClean }
        foreach ($k in $Counters.Keys) {
            $kClean = $k.ToLower() -replace '[^a-z0-9]',''
            if ($dShort.Length -gt 4 -and $kClean.Contains($dShort)) { return $k }
        }
    }

    # S6: if only one active interface and a single non-loopback counter
    $real = @()
    foreach ($k in $Counters.Keys) {
        if ($k.ToLower() -notmatch 'loopback|isatap|teredo|6to4') { $real += $k }
    }
    if ($real.Count -eq 1 -and $script:interfaces.Count -eq 1) { return $real[0] }

    return $null
}

# ============================================================
# SECTION 9 - STARTUP DEBUG
# Shows available counters and the matching result
# ============================================================
function Debug-Counters {
    Write-Host ""
    Write-Host "  === COUNTER DEBUG ===" -ForegroundColor Yellow
    $counters = Get-NetworkCounters
    if ($counters.Count -eq 0) {
        Write-Host "  NO counter available !" -ForegroundColor Red
    } else {
        $meth = ""; foreach ($v in $counters.Values) { $meth = $v.Method; break }
        Write-Host "  Methode : $meth | $($counters.Count) entrees" -ForegroundColor Cyan
        foreach ($k in $counters.Keys) {
            Write-Host "    '$k'  IN:$($counters[$k].BytesIn)  OUT:$($counters[$k].BytesOut)" `
                       -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "  Interface matching :" -ForegroundColor Cyan
    foreach ($ifName in $script:interfaces.Keys) {
        $info = $script:ActiveIfaces[$ifName]
        $desc = if ($null -ne $info) { $info.Description } else { "" }
        $cKey = Find-CounterKey -IfaceName $ifName -IfaceDesc $desc -Counters $counters
        if ($null -ne $cKey) {
            Write-Host "    [OK]   '$ifName'  ->  '$cKey'" -ForegroundColor Green
        } else {
            Write-Host "    [FAIL] '$ifName'  ->  NOT FOUND" -ForegroundColor Red
        }
    }
    Write-Host "  ========================" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================
# SECTION 10 - PER-INTERFACE BUFFER INITIALIZATION
# Each interface has 4 views (Live/Hour/Day/Week)
# + accumulateurs de consolidation
# ============================================================
function Init-InterfaceBuffers {
    param([string]$Name)

    $script:interfaces[$Name] = @{
        # -- LIVE view (1 pt / 5s, max 720 pts = 1h) ----------
        LiveTs    = @()       # Timestamps Unix ms
        LiveIn    = @()       # IN rate in Mbps
        LiveOut   = @()       # OUT rate in Mbps
        LiveCount = [int]0

        # -- HOUR view (1 pt / 30s, max 720 pts = 6h) ---------
        HourTs    = @(); HourIn    = @(); HourOut   = @(); HourCount  = [int]0

        # -- DAY view (1 pt / 5min, max 720 pts = 2.5d) -------
        DayTs     = @(); DayIn     = @(); DayOut    = @(); DayCount   = [int]0

        # -- WEEK view (1 pt / 30min, max 720 pts = 15d) ------
        WeekTs    = @(); WeekIn    = @(); WeekOut   = @(); WeekCount  = [int]0

        # -- Global statistics --------------------------------
        MaxIn     = [double]0   # Maximum IN since start
        MaxOut    = [double]0   # Maximum OUT
        SumIn     = [double]0   # Sum for average calculation
        SumOut    = [double]0
        CurIn     = [double]0   # Current value (last measurement)
        CurOut    = [double]0
        Samples   = [int]0      # Total number of measurements

        # -- HOUR consolidation accumulators (6 x 5s = 30s) --
        Acc30In   = [double]0; Acc30Out  = [double]0; Acc30N  = [int]0

        # -- DAY consolidation accumulators (60 x 5s = 5min) --
        Acc300In  = [double]0; Acc300Out = [double]0; Acc300N = [int]0

        # -- WEEK consolidation accumulators (360x5s = 30min) --
        Acc1800In = [double]0; Acc1800Out= [double]0; Acc1800N= [int]0
    }

    # Previous raw counters for differential calculation
    $script:rawCounters[$Name] = @{
        LastIn  = [long]-1   # -1 = not yet initialized
        LastOut = [long]-1
        LastTs  = [long]-1
    }
}

# ============================================================
# SECTION 11 - ADD A MEASUREMENT POINT
# Called every 5s with the computed Mbps
# Updates the 4 views and the accumulators
# ============================================================
function Add-DataPoint {
    param(
        [string]$IfaceName,
        [double]$MbpsIn,
        [double]$MbpsOut,
        [long]$Ts           # Timestamp Unix ms
    )
    $iface = $script:interfaces[$IfaceName]
    if ($null -eq $iface) { return }

    # -- Update global stats -----------------------------
    $iface.CurIn   = $MbpsIn
    $iface.CurOut  = $MbpsOut
    $iface.Samples++
    $iface.SumIn  += $MbpsIn
    $iface.SumOut += $MbpsOut
    if ($MbpsIn  -gt $iface.MaxIn)  { $iface.MaxIn  = $MbpsIn  }
    if ($MbpsOut -gt $iface.MaxOut) { $iface.MaxOut = $MbpsOut }

    # -- LIVE view: each raw point ---------------------------
    $iface.LiveTs   += $Ts
    $iface.LiveIn   += $MbpsIn
    $iface.LiveOut  += $MbpsOut
    $iface.LiveCount++
    # Sliding window: truncate on overflow
    if ($iface.LiveCount -gt $MaxPoints) {
        $cut = $iface.LiveCount - $MaxPoints
        $iface.LiveTs    = $iface.LiveTs[$cut..($iface.LiveCount-1)]
        $iface.LiveIn    = $iface.LiveIn[$cut..($iface.LiveCount-1)]
        $iface.LiveOut   = $iface.LiveOut[$cut..($iface.LiveCount-1)]
        $iface.LiveCount = $MaxPoints
    }

    # -- HOUR view: average of 6 points (30s) ----------------
    $iface.Acc30In  += $MbpsIn
    $iface.Acc30Out += $MbpsOut
    $iface.Acc30N++
    if ($iface.Acc30N -ge 6) {
        $aI = Round-Double ($iface.Acc30In  / $iface.Acc30N) 4
        $aO = Round-Double ($iface.Acc30Out / $iface.Acc30N) 4
        $iface.HourTs   += $Ts
        $iface.HourIn   += $aI
        $iface.HourOut  += $aO
        $iface.HourCount++
        if ($iface.HourCount -gt $MaxPoints) {
            $cut = $iface.HourCount - $MaxPoints
            $iface.HourTs    = $iface.HourTs[$cut..($iface.HourCount-1)]
            $iface.HourIn    = $iface.HourIn[$cut..($iface.HourCount-1)]
            $iface.HourOut   = $iface.HourOut[$cut..($iface.HourCount-1)]
            $iface.HourCount = $MaxPoints
        }
        # Reset accumulateur
        $iface.Acc30In  = [double]0
        $iface.Acc30Out = [double]0
        $iface.Acc30N   = [int]0
    }

    # -- DAY view: average of 60 points (5 min) --------------
    $iface.Acc300In  += $MbpsIn
    $iface.Acc300Out += $MbpsOut
    $iface.Acc300N++
    if ($iface.Acc300N -ge 60) {
        $aI = Round-Double ($iface.Acc300In  / $iface.Acc300N) 4
        $aO = Round-Double ($iface.Acc300Out / $iface.Acc300N) 4
        $iface.DayTs   += $Ts
        $iface.DayIn   += $aI
        $iface.DayOut  += $aO
        $iface.DayCount++
        if ($iface.DayCount -gt $MaxPoints) {
            $cut = $iface.DayCount - $MaxPoints
            $iface.DayTs    = $iface.DayTs[$cut..($iface.DayCount-1)]
            $iface.DayIn    = $iface.DayIn[$cut..($iface.DayCount-1)]
            $iface.DayOut   = $iface.DayOut[$cut..($iface.DayCount-1)]
            $iface.DayCount = $MaxPoints
        }
        $iface.Acc300In  = [double]0
        $iface.Acc300Out = [double]0
        $iface.Acc300N   = [int]0
    }

    # -- WEEK view: average of 360 points (30 min) -----------
    $iface.Acc1800In  += $MbpsIn
    $iface.Acc1800Out += $MbpsOut
    $iface.Acc1800N++
    if ($iface.Acc1800N -ge 360) {
        $aI = Round-Double ($iface.Acc1800In  / $iface.Acc1800N) 4
        $aO = Round-Double ($iface.Acc1800Out / $iface.Acc1800N) 4
        $iface.WeekTs   += $Ts
        $iface.WeekIn   += $aI
        $iface.WeekOut  += $aO
        $iface.WeekCount++
        if ($iface.WeekCount -gt $MaxPoints) {
            $cut = $iface.WeekCount - $MaxPoints
            $iface.WeekTs    = $iface.WeekTs[$cut..($iface.WeekCount-1)]
            $iface.WeekIn    = $iface.WeekIn[$cut..($iface.WeekCount-1)]
            $iface.WeekOut   = $iface.WeekOut[$cut..($iface.WeekCount-1)]
            $iface.WeekCount = $MaxPoints
        }
        $iface.Acc1800In  = [double]0
        $iface.Acc1800Out = [double]0
        $iface.Acc1800N   = [int]0
    }
}

# ============================================================
# SECTION 12 - BANDWIDTH COLLECTION
# Computes Mbps from the difference of byte counters
# Handles 32-bit overflow of WMI counters
# ============================================================
function Collect-Bandwidth {
    $counters = Get-NetworkCounters
    $nowMs    = Get-NowMs

    if ($counters.Count -eq 0) {
        Write-Host "  WARN : Network counters empty !" -ForegroundColor Red
        return
    }

    foreach ($ifName in $script:interfaces.Keys) {
        $raw  = $script:rawCounters[$ifName]
        $info = $script:ActiveIfaces[$ifName]
        $desc = if ($null -ne $info) { "$($info.Description)" } else { "" }
        if ($null -eq $raw) { continue }

        # Find the counter key matching this interface
        $cKey = Find-CounterKey -IfaceName $ifName -IfaceDesc $desc -Counters $counters
        if ($null -eq $cKey) {
            if (-not $script:debugDone) {
                Write-Host "  WARN : No counter for '$ifName'" -ForegroundColor Yellow
            }
            continue
        }

        $curIn  = [long]$counters[$cKey].BytesIn
        $curOut = [long]$counters[$cKey].BytesOut

        # First pass: initialization only, no calculation
        if ($raw.LastTs -lt 0) {
            $raw.LastIn  = $curIn
            $raw.LastOut = $curOut
            $raw.LastTs  = $nowMs
            Write-Host "  Counter init OK : '$ifName' -> '$cKey'" -ForegroundColor Green
            continue
        }

        # Duration in seconds since the last measurement
        $dtMs = $nowMs - $raw.LastTs
        if ($dtMs -lt 100) { continue }   # Trop rapide, ignorer
        $dtSec = [double]$dtMs / 1000.0

        # Byte difference
        $diffIn  = $curIn  - $raw.LastIn
        $diffOut = $curOut - $raw.LastOut

        # Handle 32-bit overflow of WMI counters
        # (counters wrap to 0 after 4,294,967,295)
        $ov32 = [long]4294967295 + [long]1
        if ($diffIn  -lt 0 -and $diffIn  -gt -$ov32) { $diffIn  = $diffIn  + $ov32 }
        if ($diffOut -lt 0 -and $diffOut -gt -$ov32) { $diffOut = $diffOut + $ov32 }
        # Residual negative value = counter reset (reboot)
        if ($diffIn  -lt 0) { $diffIn  = [long]0 }
        if ($diffOut -lt 0) { $diffOut = [long]0 }

        # Convert bytes/s -> Mbps
        # Formula: (bytes / seconds) * 8 bits/byte / 1,000,000 bits/Mbit
        $mbpsIn  = [double]$diffIn  / $dtSec * 8.0 / 1000000.0
        $mbpsOut = [double]$diffOut / $dtSec * 8.0 / 1000000.0

        # Sanity check: impossible value (counter bug or unhandled overflow)
        if ($mbpsIn  -gt 200000 -or $mbpsIn  -lt 0) { $mbpsIn  = [double]0 }
        if ($mbpsOut -gt 200000 -or $mbpsOut -lt 0) { $mbpsOut = [double]0 }

        Add-DataPoint -IfaceName $ifName -MbpsIn $mbpsIn -MbpsOut $mbpsOut -Ts $nowMs

        # Save for the next iteration
        $raw.LastIn  = $curIn
        $raw.LastOut = $curOut
        $raw.LastTs  = $nowMs
    }

    $script:debugDone = $true
}

# ============================================================
# SECTION 13 - SERIALIZE A VIEW TO JSON
# Produces a JS array [{t:...,i:...,o:...}, ...]
# Double-ToJs is mandatory to avoid the FR locale comma
# ============================================================
function Serialize-View {
    param(
        [array]$Ts,     # Tableau de timestamps
        [array]$In,     # Array of IN rates (Mbps)
        [array]$Out,    # Array of OUT rates (Mbps)
        [int]$Count     # Number of valid points
    )
    $pts = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $t  = [long]$Ts[$i]
        $vi = Double-ToJs ([double]$In[$i])
        $vo = Double-ToJs ([double]$Out[$i])
        $pts += "{t:$t,i:$vi,o:$vo}"
    }
    return "[" + ($pts -join ",") + "]"
}

# ============================================================
# SECTION 14 - WRITE THE network_data.js FILE
# This file is reloaded by the browser every 2s
# It defines window.MD with all current data
# ============================================================
function Write-DataJs {
    # Compute the elapsed run time
    $elapsed = Get-ElapsedSec
    $hh = [int]($elapsed / 3600)
    $mm = [int](($elapsed % 3600) / 60)
    $ss = $elapsed % 60
    $durStr = "$("{0:D2}" -f $hh)h $("{0:D2}" -f $mm)m $("{0:D2}" -f $ss)s"
    $nowStr = Get-Date -Format "HH:mm:ss"

    # Build the interfaces JSON
    $ifParts = @()
    foreach ($ifName in $script:interfaces.Keys) {
        $iface    = $script:interfaces[$ifName]
        $info     = $script:ActiveIfaces[$ifName]
        $descr    = ""
        $linkMbps = [double]0
        if ($null -ne $info) {
            $descr    = "$($info.Description)" -replace '"','\"'
            $linkMbps = [double]$info.LinkSpeedMbps
        }

        # Serialize the 4 views
        $liveJs = Serialize-View $iface.LiveTs $iface.LiveIn $iface.LiveOut $iface.LiveCount
        $hourJs = Serialize-View $iface.HourTs $iface.HourIn $iface.HourOut $iface.HourCount
        $dayJs  = Serialize-View $iface.DayTs  $iface.DayIn  $iface.DayOut  $iface.DayCount
        $weekJs = Serialize-View $iface.WeekTs $iface.WeekIn $iface.WeekOut $iface.WeekCount

        # Compute the global averages
        $avgIn  = [double]0
        $avgOut = [double]0
        if ($iface.Samples -gt 0) {
            $avgIn  = Round-Double ($iface.SumIn  / $iface.Samples) 4
            $avgOut = Round-Double ($iface.SumOut / $iface.Samples) 4
        }

        $safeName = "$ifName" -replace '"','\"'
        $ifParts += """$safeName"":{" +
            """desc"":""$descr""," +
            """link"":$(Double-ToJs $linkMbps)," +
            """curIn"":$(Double-ToJs $iface.CurIn)," +
            """curOut"":$(Double-ToJs $iface.CurOut)," +
            """maxIn"":$(Double-ToJs $iface.MaxIn)," +
            """maxOut"":$(Double-ToJs $iface.MaxOut)," +
            """avgIn"":$(Double-ToJs $avgIn)," +
            """avgOut"":$(Double-ToJs $avgOut)," +
            """samples"":$($iface.Samples)," +
            """live"":$liveJs," +
            """hour"":$hourJs," +
            """day"":$dayJs," +
            """week"":$weekJs}"
    }

    # Serialize the Y scale mode
    $ysModeJs    = if ($script:YScaleMode -eq "auto") {
                       """auto"""
                   } else {
                       "$(Double-ToJs ([double]$script:YScaleMode))"
                   }
    $thrEnabledJs = if ($script:ThresholdEnabled) { "true" } else { "false" }

    # Write the JS file
    $js = "window.MD={" +
          "ifaces:{" + ($ifParts -join ",") + "}," +
          "threshold:$(Double-ToJs ([double]$script:ThresholdAlert))," +
          "thresholdEnabled:$thrEnabledJs," +
          "yScaleMode:$ysModeJs," +
          "dur:""$durStr""," +
          "now:""$nowStr""," +
          "startMs:$($script:startMs)" +
          "};"

    try { $js | Set-Content -Path $dataFile -Encoding UTF8 -ErrorAction Stop } catch {}
}

# ============================================================
# SECTION 15 - READ BROWSER COMMANDS
# The browser can write to mrtg_cmd.js to change
# threshold, yScale, etc. on the PS side
# ============================================================
function Read-CmdFile {
    if (-not (Test-Path $cmdFile)) { return }
    try {
        $raw = Get-Content -Path $cmdFile -Raw -ErrorAction SilentlyContinue
        if (-not $raw) {
            Remove-Item $cmdFile -Force -ErrorAction SilentlyContinue
            return
        }

        # Update the alarm threshold
        if ($raw -match '"threshold"\s*:\s*(\d+(?:[.,]\d+)?)') {
            $tStr = $Matches[1] -replace ',','.'
            $newT = [double]0
            try { $newT = [double]$tStr } catch {}
            if ($newT -gt 0 -and $newT -le 200000) {
                $script:ThresholdAlert = $newT
                Write-Host "  Threshold -> $newT Mbps" -ForegroundColor Cyan
            }
        }

        # Enable/disable the threshold
        if ($raw -match '"thresholdEnabled"\s*:\s*(true|false)') {
            $script:ThresholdEnabled = ($Matches[1] -eq "true")
            Write-Host "  ThresholdEnabled -> $($script:ThresholdEnabled)" -ForegroundColor Cyan
        }

        # Change the Y scale mode
        if ($raw -match '"yScale"\s*:\s*"([^"]+)"') {
            $newY = $Matches[1]
            if ($newY -eq "auto") {
                $script:YScaleMode = "auto"
            } else {
                $yStr = $newY -replace ',','.'
                $yv   = [double]0
                try { $yv = [double]$yStr } catch {}
                if ($yv -gt 0) { $script:YScaleMode = "$yv" }
            }
        }

        Remove-Item $cmdFile -Force -ErrorAction SilentlyContinue
    } catch {}
}

# ============================================================
# SECTION 16 — CHARGEMENT DE CHART.JS (OFFLINE)
# Look for chartjs.min.js in several local locations
# Fallback: attempt CDN download
# ============================================================
function Get-ChartJsTag {
    $candidates = @(
        "$scriptTemp\chartjs.min.js",
        "$scriptTemp\chart.min.js",
        "$env:USERPROFILE\Documents\chartjs.min.js",
        "$env:USERPROFILE\Documents\chart.min.js",
        "$env:USERPROFILE\Desktop\chartjs.min.js"
    )

    Write-Host "  Chart.js : local search..." -ForegroundColor Cyan
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        if (Test-Path $c) {
            $src = Get-Content -Path $c -Raw -ErrorAction SilentlyContinue
            if ($src -and $src.Length -gt 10000) {
                Write-Host "  Chart.js : OK — $c ($([int]($src.Length/1024)) KB)" `
                           -ForegroundColor Green
                # Copy to the working folder if needed
                if ($c -ne "$scriptTemp\chartjs.min.js") {
                    try {
                        $src | Set-Content -Path "$scriptTemp\chartjs.min.js" `
                               -Encoding UTF8 -ErrorAction SilentlyContinue
                    } catch {}
                }
                return "<script>`n$src`n</script>"
            }
        }
    }

    # Attempt CDN download (network available)
    Write-Host "  Chart.js : attempting CDN download..." -ForegroundColor Yellow
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent","PowerShell/5.1")
        $src = $wc.DownloadString(
            "https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"
        )
        if ($src -and $src.Length -gt 10000) {
            $src | Set-Content -Path "$scriptTemp\chartjs.min.js" `
                   -Encoding UTF8 -ErrorAction SilentlyContinue
            Write-Host "  Chart.js : downloaded OK" -ForegroundColor Green
            return "<script>`n$src`n</script>"
        }
    } catch {
        Write-Host "  Chart.js : download failed" -ForegroundColor Red
    }

    Write-Host "  >> ACTION : Drop chartjs.min.js into : $scriptTemp" -ForegroundColor Yellow
    # Inline CDN fallback (requires internet in the browser)
    return '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>'
}

# ============================================================
# SECTION 17 - OPEN THE BROWSER
# ============================================================
function Open-Browser {
    param([string]$FilePath)
    $browsers = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "C:\Program Files\Mozilla Firefox\firefox.exe"
    )
    $found = $null
    foreach ($b in $browsers) { if (Test-Path $b) { $found = $b; break } }

    # file:// URL (Chromium's --app mode requires a URL)
    $fileUrl = "file:///" + ($FilePath -replace '\\','/')

    if ($found -and ($found -like "*msedge.exe" -or $found -like "*chrome.exe")) {
        Write-Host "  Browser : $(Split-Path $found -Leaf) (app mode - monitored)" -ForegroundColor Green
        # Application mode + dedicated profile = clean, monitorable process.
        # Suppress pop-ups (sync / sign-in / translation).
        $bargs = @(
            "--app=$fileUrl",
            "--user-data-dir=$profileDir",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-sync",
            "--disable-features=msEdgeSyncBubble,msImplicitSignin,Translate,TranslateUI,msTranslateBubble"
        )
        try {
            $proc = Start-Process -FilePath $found -PassThru -ArgumentList $bargs
            return $proc
        } catch {
            # Fallback: simple open if app mode fails (no auto-stop)
            Start-Process -FilePath $found -ArgumentList "`"$FilePath`""
            return $null
        }
    }
    elseif ($found) {
        Write-Host "  Browser : $(Split-Path $found -Leaf) (auto-stop unavailable)" -ForegroundColor Yellow
        Start-Process -FilePath $found -ArgumentList "`"$FilePath`""
        return $null
    }
    else {
        Write-Host "  Browser : default (auto-stop unavailable)" -ForegroundColor Yellow
        Start-Process $FilePath
        return $null
    }
}

# Returns $true while the dashboard window is open. Primary signal: ANY
# Edge/Chrome process whose command line uses our dedicated profile dir.
# This is robust to Chromium's launcher hand-off (where the spawned PID
# exits immediately even though the real browser window stays open).
# Fallback (if CIM/WMI is unavailable): the spawned process handle.
function Test-BrowserOpen {
    param([string]$ProfileDir)
    try {
        $hits = Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction Stop |
                Where-Object { $_.CommandLine -like "*$ProfileDir*" }
        if ($hits) { return $true } else { return $false }
    } catch {
        try { return (-not $script:browserProc.HasExited) } catch { return $true }
    }
}

# ============================================================
# SECTION 18 - HTML GENERATION
# Generates dashboard.html with embedded Chart.js
# The HTML is static; data arrives via network_data.js
# ============================================================
function Write-HtmlOnce {
    $dataFileJs  = $dataFile -replace '\\','\\\\'
    $chartJsTag  = Get-ChartJsTag
    $initThr     = $ThresholdAlertMbps
    $initThrEn   = if ($ThresholdEnabled) { "true" } else { "false" }
    $initYScale  = if ($script:YScaleMode -eq "auto") { "auto" } else { $script:YScaleMode }

    $html = @"
<!DOCTYPE html>
<html lang="fr" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>PS-MRTG v1.22 - MRTG Bandwidth Monitor</title>
$chartJsTag
<style>
/* -- CSS variables, dark theme (default) ------------------- */
:root{
  --bg:#1a1a2e;--surface:#16213e;--surface2:#0d1b2a;--surface3:#0a1220;
  --border:#0f3460;--border2:#1e3050;--border3:#0a1830;
  --text:#e0e0e0;--text2:#a0b0c0;--text3:#556677;--text4:#778899;
  --accent:#4cc9f0;--accent2:#0f3460;
  --ok:#4ade80;--warn:#fb923c;--danger:#f87171;
  --tab1-bg:#0d1b2a;--tab1-act:#16213e;--tab1-c:#778899;
  --tab1-act-c:#4cc9f0;--tab1-bd:#0f3460;
  --tab2-bg:#0a1220;--tab2-act:#16213e;--tab2-c:#556677;
  --tab2-act-c:#e0e0e0;--tab2-bd:#0f2040;
  --inp-bg:#0d1b2a;--inp-bd:#0f3460;
  --btn-bg:#0f3460;--btn-c:#4cc9f0;
  --btn2-bg:rgba(248,113,113,.15);--btn2-c:#f87171;
  --in-c:rgba(74,222,128,.95);--in-f:rgba(74,222,128,.12);
  --out-c:rgba(76,201,240,.95);--out-f:rgba(76,201,240,.10);
  --thr-gray:rgba(180,180,200,.45);--thr-red:rgba(248,113,113,.85);
  --grid:rgba(80,80,120,.15);--grid2:rgba(80,80,120,.2);
  --tick:#556677;--tickY:#a0b0c0;--tickU:#778899;
  --sb-bg:#0d1117;--sb-th:#1e3050;
  --cell-bg:#0d1b2a;--cell-bd:#1e3050;
  --opt-bg:#0a1520;--opt-bd:#0f3460;
}
/* -- CSS variables, light theme --------------------------── */
[data-theme="light"]{
  --bg:#f0f4f8;--surface:#ffffff;--surface2:#e8edf5;--surface3:#dde4ee;
  --border:#b0c0d8;--border2:#c8d4e8;--border3:#d0dcea;
  --text:#0f1923;--text2:#3a5070;--text3:#8090a8;--text4:#607090;
  --accent:#0063be;--accent2:#dde9f8;--ok:#007a5e;--warn:#b86000;--danger:#c0202e;
  --tab1-bg:#e8edf5;--tab1-act:#ffffff;--tab1-c:#607090;
  --tab1-act-c:#0063be;--tab1-bd:#b0c0d8;
  --tab2-bg:#dde4ee;--tab2-act:#ffffff;--tab2-c:#8090a8;
  --tab2-act-c:#0f1923;--tab2-bd:#c0cfe0;
  --inp-bg:#ffffff;--inp-bd:#b0c0d8;
  --btn-bg:#dde9f8;--btn-c:#0063be;
  --btn2-bg:rgba(192,32,46,.08);--btn2-c:#c0202e;
  --in-c:rgba(0,140,80,.95);--in-f:rgba(0,180,100,.10);
  --out-c:rgba(0,99,190,.95);--out-f:rgba(0,99,190,.08);
  --thr-gray:rgba(100,120,150,.5);--thr-red:rgba(192,32,46,.8);
  --grid:rgba(100,120,160,.12);--grid2:rgba(100,120,160,.18);
  --tick:#8090a8;--tickY:#3a5070;--tickU:#607090;
  --sb-bg:#e8edf5;--sb-th:#b0c0d8;
  --cell-bg:#f8fafc;--cell-bd:#c8d4e8;
  --opt-bg:#eef2f8;--opt-bd:#b0c0d8;
}
/* ── Reset & base ────────────────────────────────────────── */
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);
     font-family:'Segoe UI',Consolas,monospace;
     display:flex;flex-direction:column;height:100vh;overflow:hidden;
     transition:background .25s,color .25s}

/* ── Header ──────────────────────────────────────────────── */
.hdr{background:var(--surface);padding:6px 16px;
     border-bottom:2px solid var(--border);
     display:flex;align-items:center;justify-content:space-between;
     gap:10px;min-height:42px;flex-shrink:0}
.hl{display:flex;align-items:center;gap:10px}
.hdr h1{font-size:1.02em;font-weight:bold;white-space:nowrap}
.vtag{background:var(--accent2);color:var(--accent);font-size:.7em;
      padding:2px 7px;border-radius:10px;font-weight:bold}
.hr2{display:flex;gap:8px;align-items:center;flex-shrink:0}
/* Blinking dot indicating monitoring activity */
.hdot{width:8px;height:8px;border-radius:50%;background:var(--ok);
      animation:pl 1.2s infinite;flex-shrink:0}
.dur{color:var(--warn);font-size:.83em;font-weight:bold;white-space:nowrap}
.nowt{color:var(--text3);font-size:.8em;white-space:nowrap}
.thbtn{background:transparent;border:1px solid var(--border2);color:var(--text3);
       font-size:.73em;padding:3px 9px;border-radius:4px;cursor:pointer;white-space:nowrap}
.thbtn:hover{filter:brightness(1.25)}
@keyframes pl{0%,100%{opacity:1}50%{opacity:.25}}

/* -- Level 1 tabs: interface selection --------------------── */
.tabs1{background:var(--tab1-bg);border-bottom:2px solid var(--border);
       display:flex;align-items:flex-end;padding:0 12px;
       gap:2px;flex-shrink:0;overflow-x:auto;min-height:36px}
.tabs1::-webkit-scrollbar{height:3px}
.tabs1::-webkit-scrollbar-thumb{background:var(--sb-th)}
.t1btn{padding:7px 15px;font-size:.8em;font-weight:600;color:var(--tab1-c);
       cursor:pointer;border-radius:6px 6px 0 0;border:1px solid transparent;
       border-bottom:none;white-space:nowrap;transition:all .15s;
       background:transparent;display:flex;align-items:center;gap:6px}
.t1btn:hover{color:var(--tab1-act-c);background:var(--surface2)}
.t1btn.a{background:var(--tab1-act);color:var(--tab1-act-c);
          border-color:var(--tab1-bd);border-bottom-color:var(--tab1-act)}
/* Small blinking green dot in each interface tab */
.t1dot{width:7px;height:7px;border-radius:50%;background:var(--ok);
       animation:pl 1.4s infinite;flex-shrink:0}

/* -- Per-interface panel --------------------------------- */
.iface-panel{display:none;flex-direction:column;flex:1;overflow:hidden;min-height:0}
.iface-panel.a{display:flex}

/* ── Barre de stats (IN/OUT/Max/Moy) ────────────────────── */
.ibar{background:var(--surface2);padding:0 14px;
      border-bottom:1px solid var(--border2);
      display:flex;align-items:center;font-size:.78em;
      height:26px;flex-shrink:0;overflow:hidden}
.sp{width:1px;height:13px;background:var(--border2);margin:0 9px;flex-shrink:0}
.si{display:flex;gap:3px;align-items:center;flex-shrink:0;white-space:nowrap}
.sl{color:var(--text3)}.sv{font-weight:bold}
.sin{color:var(--ok)}.sout{color:var(--accent)}.sn{color:var(--text2)}

/* -- Level 2 tabs: time view selection ------------------- */
.tabs2{background:var(--tab2-bg);padding:0 12px;
       display:flex;align-items:center;gap:3px;
       border-bottom:1px solid var(--border2);min-height:32px;flex-shrink:0}
.t2btn{padding:4px 12px;font-size:.75em;font-weight:600;color:var(--tab2-c);
       cursor:pointer;border-radius:4px;white-space:nowrap;transition:all .15s;
       border:1px solid transparent;background:transparent}
.t2btn:hover{color:var(--tab2-act-c);background:var(--surface2)}
.t2btn.a{background:var(--tab2-act);color:var(--tab2-act-c);border-color:var(--tab2-bd)}
.t2all{color:var(--accent)}.t2all.a{background:var(--accent2);border-color:var(--accent)}

/* -- Chart area ------------------------------------------- */
.gcont{flex:1;overflow:hidden;display:flex;flex-direction:column;min-height:0}
/* Individual view (full width) */
.gview{display:none;flex:1;flex-direction:column;
       padding:10px 12px 6px;overflow:hidden;min-height:0}
.gview.a{display:flex}
.gview canvas{flex:1;min-height:0}
/* "All" view: 2x2 grid of the 4 charts */
.gall{display:none;flex:1;overflow:hidden;
      grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;
      gap:6px;padding:6px 12px}
.gall.a{display:grid}
.gcell{background:var(--cell-bg);border:1px solid var(--cell-bd);
       border-radius:5px;padding:6px 8px;
       display:flex;flex-direction:column;overflow:hidden;min-height:0}
/* Header of a chart cell (label + mini stats) */
.gclbl{font-size:.7em;font-weight:bold;color:var(--text3);margin-bottom:3px;
       flex-shrink:0;display:flex;justify-content:space-between;align-items:center}
.gclbl-s{font-size:.85em;color:var(--text4)}
.gcell canvas{flex:1;min-height:0}

/* -- Footer: snapshot button + Options panel -------------── */
.fbar{background:var(--surface);border-top:1px solid var(--border);
      padding:0;display:flex;flex-direction:column;flex-shrink:0}
.fbar-main{display:flex;align-items:center;gap:10px;
           padding:5px 14px;flex-wrap:wrap;min-height:40px}
/* Options panel (foldable) */
.fbar-opts{background:var(--opt-bg);border-top:1px solid var(--opt-bd);
           padding:7px 14px;display:none;flex-wrap:wrap;gap:14px;align-items:center}
.fbar-opts.open{display:flex}
.opt-group{display:flex;align-items:center;gap:7px;flex-wrap:wrap}
.opt-title{color:var(--text3);font-size:.68em;font-weight:700;
           text-transform:uppercase;letter-spacing:.5px;white-space:nowrap}
.opt-sep{width:1px;height:22px;background:var(--border2);flex-shrink:0}

/* -- Options panel controls -------------------------------- */
.ci{display:flex;align-items:center;gap:5px}
.ci label{color:var(--text3);font-size:.76em;white-space:nowrap}
/* Point size slider */
.sg{display:flex;align-items:center;gap:5px}
.sg label{color:var(--text3);font-size:.75em;white-space:nowrap}
.sg .sv2{color:var(--accent);font-weight:bold;font-size:.78em;min-width:48px}
input[type=range]{width:90px;accent-color:var(--accent);cursor:pointer}
input[type=number]{background:var(--inp-bg);border:1px solid var(--inp-bd);
                   color:var(--accent);padding:3px 7px;border-radius:4px;
                   font-size:.8em;width:85px;
                   font-family:Consolas,monospace;font-weight:bold}
input[type=number]:focus{outline:2px solid var(--accent)}
/* Threshold enable checkbox */
.thr-toggle{display:flex;align-items:center;gap:6px;cursor:pointer;
            font-size:.76em;color:var(--text2);user-select:none}
.thr-toggle input[type=checkbox]{width:14px;height:14px;cursor:pointer;
                                  accent-color:var(--danger)}
select{background:var(--inp-bg);border:1px solid var(--inp-bd);color:var(--accent);
       padding:3px 6px;border-radius:4px;font-size:.78em;
       font-family:Consolas,monospace;font-weight:bold;cursor:pointer}
/* Boutons */
.btn{padding:4px 11px;border:1px solid var(--border2);border-radius:4px;
     cursor:pointer;font-size:.76em;font-weight:bold;white-space:nowrap;
     background:var(--btn-bg);color:var(--btn-c);transition:opacity .15s}
.btn:hover{opacity:.8}
.btn-opt{background:transparent;border-color:var(--text3);color:var(--text3);
         font-size:.72em;padding:3px 9px}
.btn-opt:hover{color:var(--accent);border-color:var(--accent);opacity:1}
.btnsnap{background:var(--btn2-bg);color:var(--btn2-c);border-color:var(--btn2-c)}
/* Legend IN/OUT/10M/Threshold */
.leg{display:flex;gap:10px;align-items:center;margin-left:auto}
.legitem{display:flex;align-items:center;gap:4px;font-size:.73em;color:var(--text2)}
.legline{width:18px;height:3px;border-radius:2px}
.legin{background:var(--ok)}.legout{background:var(--accent)}
/* Y scale badge in the header */
.yscale-badge{font-size:.72em;font-weight:bold;background:var(--accent2);
              color:var(--accent);padding:2px 8px;border-radius:10px;
              border:1px solid var(--border2);white-space:nowrap}
/* Scrollbar custom */
::-webkit-scrollbar{width:5px;height:5px}
::-webkit-scrollbar-track{background:var(--sb-bg)}
::-webkit-scrollbar-thumb{background:var(--sb-th);border-radius:3px}
</style>
</head>
<body>

<!-- ── HEADER ─────────────────────────────────────────────── -->
<div class="hdr">
  <div class="hl">
    <span class="hdot"></span>
    <h1>PS&#8209;MRTG&nbsp;
      <span style="color:var(--text3);font-weight:normal;font-size:.85em">
        MRTG Bandwidth Monitor
      </span>
    </h1>
    <span class="vtag">v1.22</span>
  </div>
  <div class="hr2">
    <!-- Current Y scale mode badge -->
    <span class="yscale-badge" id="ysBadge">Y: Auto</span>
    <span class="nowt" id="nowLbl">--:--:--</span>
    <span class="dur"  id="durLbl">00h 00m 00s</span>
    <button class="thbtn" id="thBtn" onclick="togTheme()">&#9728; Light</button>
  </div>
</div>

<!-- LEVEL 1 TABS: interfaces (generated dynamically) -->
<div class="tabs1" id="tabs1"></div>

<!-- -- PER-INTERFACE PANELS (generated dynamically) -------- -->
<div id="panels" style="flex:1;display:flex;flex-direction:column;
     overflow:hidden;min-height:0"></div>

<!-- ── FOOTER ─────────────────────────────────────────────── -->
<div class="fbar">
  <!-- Barre principale footer -->
  <div class="fbar-main">
    <button class="btn btnsnap" onclick="exportSnapshot()">
      &#128247; Snapshot HTML
    </button>
    <!-- Color legend -->
    <div class="leg">
      <div class="legitem">
        <div class="legline legin"></div>&#8595; IN
      </div>
      <div class="legitem">
        <div class="legline legout"></div>&#8593; OUT
      </div>
      <div class="legitem" style="color:var(--text3)">
        <div style="width:18px;height:2px;
             border-top:2px dashed rgba(180,180,200,.45)"></div>
        10M
      </div>
      <div class="legitem" id="legThr" style="color:var(--danger)">
        <div style="width:18px;height:2px;
             border-top:2px dashed rgba(248,113,113,.85)"></div>
        Threshold
      </div>
    </div>
    <button class="btn btn-opt" id="optToggle" onclick="togOpts()">
      &#9660; Options
    </button>
  </div>

  <!-- Options panel (foldable, closed by default) -->
  <div class="fbar-opts" id="fbarOpts">

    <!-- Group: Alarm threshold -->
    <div class="opt-group">
      <span class="opt-title">Alarm threshold</span>
      <!-- Checkbox to enable/disable the threshold -->
      <label class="thr-toggle">
        <input type="checkbox" id="thrEnabled" onchange="toggleThr()">
        <span>Active</span>
      </label>
      <!-- Value field + apply button -->
      <div class="ci" id="thrInputGroup">
        <input type="number" id="thrInput" value="$initThr" min="1" max="200000">
        <span style="color:var(--text3);font-size:.76em">Mbps</span>
        <button class="btn" onclick="applyThr()">OK</button>
      </div>
    </div>

    <div class="opt-sep"></div>

    <!-- Group: Y scale -->
    <div class="opt-group">
      <span class="opt-title">Y scale</span>
      <select id="ysSelect" onchange="applyYScale()">
        <option value="auto">Auto (steps)</option>
        <option value="10">10 Mbps</option>
        <option value="20">20 Mbps</option>
        <option value="50">50 Mbps</option>
        <option value="100">100 Mbps</option>
        <option value="200">200 Mbps</option>
        <option value="500">500 Mbps</option>
        <option value="1000">1 Gbps</option>
        <option value="2000">2 Gbps</option>
        <option value="5000">5 Gbps</option>
        <option value="10000">10 Gbps</option>
        <option value="100000">100 Gbps</option>
        <option value="200000">200 Gbps</option>
      </select>
    </div>

    <div class="opt-sep"></div>

    <!-- Group: Point size -->
    <div class="opt-group">
      <span class="opt-title">Points</span>
      <div class="sg">
        <label>Taille :</label>
        <input type="range" id="sPtSize" min="0" max="8" step="0.5" value="0.5"
               oninput="updPtSize(this.value)">
        <span class="sv2" id="vPtSize">0.5 px</span>
      </div>
    </div>

  </div>
</div>

<script>
// ============================================================
// CONFIG
// ============================================================
var DJP = '$dataFileJs';  // Path of the network_data.js file

// ============================================================
// GLOBAL UI STATE
// ============================================================
var MD          = null;    // Last data received from PS
var charts      = {};      // Registry of Chart instances (key = sid_view_suf)
var curIface    = null;    // Currently displayed active interface
var curViews    = {};      // Active view per interface (all/live/hour/day/week)
var darkMode    = true;    // Current theme
var optsOpen    = false;   // Options panel open/closed
var ifaceOrder  = [];      // Interface order (for consistency)
var initialized = false;   // HTML panels already built

// Automatic Y scale steps (Mbps) - fine 1-2-5 progression
// v1.10: intermediate steps added (notably 200 and 500 Mbps)
//    to avoid abrupt 100 Mbps -> 1 Gbps jumps.
var Y_STEPS = [1, 2, 5, 10, 20, 50, 100, 200, 500,
               1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000];

// Options settings - initialized from PS only once (uiInitDone)
var thrVal      = $initThr;       // Threshold value in Mbps
var thrEnabled  = $initThrEn;     // Threshold active or not
var yScaleMode  = '$initYScale';  // "auto" or numeric value
var ptSize      = 0.5;            // Point size in px (default 0.5)

// CRITICAL FLAG: PS initializes the UI only once on load
// Without this flag, each 2s cycle would overwrite the user's choices
var uiInitDone  = false;

var VIEWS = ['live','hour','day','week'];
// Short label shown next to each chart: RESOLUTION + LOOK-BACK.
// v1.14: the covered period (the "look-back") is now explicit.
//    Fix: the "hour" view actually covers 6h (not 1h).
var VL    = {
  live : 'Live \u00B7 1h (5s)',
  hour : '6h (30s)',
  day  : '2.5d (5min)',
  week : '15d (30min)'
};
// Tooltip (title): full look-back explanation, on hover.
var VLT   = {
  live : 'Real time \u2014 1 hour look-back (1 point / 5 s)',
  hour : '6 hour look-back (1 point / 30 s)',
  day  : '2.5 day look-back (1 point / 5 min)',
  week : '15 day look-back (1 point / 30 min)'
};
// v1.15: time window duration of each view (in ms).
//   Used to fix the X axis domain -> data is drawn at its
//   real position (a partial history only occupies a fraction of
//   the width, not the whole width).
var VWIN  = {
  live : 3600000,      //  1 h   = 60 * 60 * 1000
  hour : 21600000,     //  6 h   = 6 * 3600 * 1000
  day  : 216000000,    //  2,5 j = 60 * 3600 * 1000
  week : 1296000000    //  15 j  = 15 * 24 * 3600 * 1000
};

// ============================================================
// DARK/LIGHT THEME
// ============================================================
function togTheme(){
  darkMode = !darkMode;
  document.documentElement.setAttribute('data-theme', darkMode ? 'dark' : 'light');
  document.getElementById('thBtn').innerHTML = darkMode ? '&#9728; Light' : '&#9790; Dark';
  redrawAll();
}

// ============================================================
// OPTIONS PANEL (foldable)
// ============================================================
function togOpts(){
  optsOpen = !optsOpen;
  var el = document.getElementById('fbarOpts');
  var bt = document.getElementById('optToggle');
  if(optsOpen){ el.classList.add('open');    bt.innerHTML = '&#9650; Options'; }
  else        { el.classList.remove('open'); bt.innerHTML = '&#9660; Options'; }
}

// ============================================================
// HELPERS UTILITAIRES
// ============================================================

// Reads a CSS variable defined in :root
function gcs(v){ return getComputedStyle(document.documentElement).getPropertyValue(v).trim(); }

// Escapes HTML to prevent injection
function escH(s){
  if(!s) return '';
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// Turns a name into a CSS-safe identifier (alphanum + _)
function sid(s){ return s.replace(/[^a-zA-Z0-9]/g,'_'); }

// Formats a Unix ms timestamp for the X axis, by view.
// v1.13: multi-day views (day/week) show date AND time
//    on a SINGLE line, in "DD/MM HH:MM" format. The ticks
//    are spaced (3 in grid / 6 in full screen) to ensure no
//    label overlaps.
function ft(ms, view){
  var n = parseInt(ms,10);
  if(isNaN(n) || n <= 0) return '';
  var d  = new Date(n);
  var hh = ('0'+d.getHours()).slice(-2);
  var mm = ('0'+d.getMinutes()).slice(-2);
  var ss = ('0'+d.getSeconds()).slice(-2);
  var dm = ('0'+d.getDate()).slice(-2)+'/'+('0'+(d.getMonth()+1)).slice(-2);
  // Live (~1h): second-level precision
  if(view === 'live') return hh+':'+mm+':'+ss;
  // 1h (~6h): hour:minute (always the same day on screen)
  if(view === 'hour') return hh+':'+mm;
  // Day (2.5d) & Week (15d): date + time on a single line
  return dm+' '+hh+':'+mm;
}

// Formats a full timestamp for the tooltip (tooltip title).
// v1.15: "DD/MM HH:MM:SS" - the X axis being numeric (ms), we must
//    reformat the tooltip title ourselves.
function ftTip(ms){
  var n = parseInt(ms,10);
  if(isNaN(n) || n <= 0) return '';
  var d = new Date(n);
  return ('0'+d.getDate()).slice(-2)+'/'+('0'+(d.getMonth()+1)).slice(-2)+' '+
         ('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2)+':'+
         ('0'+d.getSeconds()).slice(-2);
}

// Formats an Mbps value into a readable string (1 line - tooltips/stats)
function fmb(v){
  v = parseFloat(v);
  if(isNaN(v) || v < 0) return '--';
  if(v === 0)   return '0 Kbps';
  if(v >= 1000) return (v/1000).toFixed(2)+' Gbps';
  if(v >= 1)    return v.toFixed(2)+' Mbps';
  return (v*1000).toFixed(0)+' Kbps';
}

// ============================================================
// Y AXIS TICK FORMATTING (multi-line)
// v1.9: for a readable axis, return an ARRAY to Chart.js v4
//    -> the value shows on line 1, the unit on line 2.
//    The unit is chosen by value (like fmb): 200->"200 Mbps",
//    1000->"1 Gbps", which stays natural even on a mixed axis.
// ============================================================
function yTick(value){
  var v = parseFloat(value);
  if(isNaN(v) || v < 0) return '';
  if(v === 0) return '0';                 // zero stays on 1 line, no unit
  if(v >= 1000){
    var g = v / 1000;
    var gs = (g % 1 === 0) ? String(g)
            : g.toFixed(2).replace(/0+$/,'').replace(/\.$/,'');
    return [gs, 'Gbps'];                   // line 1 = value, line 2 = unit
  }
  if(v >= 1){
    var ms = (v % 1 === 0) ? String(v) : v.toFixed(1);
    return [ms, 'Mbps'];
  }
  return [String(Math.round(v * 1000)), 'Kbps'];
}

// Updates the textContent of an element by its id
function sel(id,v){ var e=document.getElementById(id); if(e) e.textContent=v; }

// ============================================================
// Y SCALE - STEP CALCULATION
// ============================================================

// Computes yMax (step) based on the mode and a given max value.
// v1.9: the optional inclusion of the threshold is handled BY THE CALLER
//    (updateChartsForIface), which passes max(data, threshold) so the
//    alarm line stays visible and the 4 views share the same height.
function calcYMax(dataMax){
  if(yScaleMode !== 'auto'){ return parseFloat(yScaleMode) || 1000; }
  // Auto mode: first step that contains the value
  for(var i=0; i<Y_STEPS.length; i++){
    if(dataMax <= Y_STEPS[i]){ return Y_STEPS[i]; }
  }
  return Y_STEPS[Y_STEPS.length-1];
}

// Updates the Y: badge in the header
function updateYBadge(){
  var badge = document.getElementById('ysBadge');
  if(!badge) return;
  if(yScaleMode === 'auto'){
    badge.textContent = 'Y: Auto';
    badge.style.color = '';
    badge.style.background = '';
    badge.style.borderColor = '';
  } else {
    badge.textContent = 'Y: ' + fmb(parseFloat(yScaleMode));
    badge.style.color = 'var(--warn)';
    badge.style.background = 'rgba(251,146,60,.12)';
    badge.style.borderColor = 'rgba(251,146,60,.4)';
  }
}

// Syncs the Y scale select with the current yScaleMode
function syncYSelect(){
  var s = document.getElementById('ysSelect');
  if(!s) return;
  for(var i=0; i<s.options.length; i++){
    if(s.options[i].value === String(yScaleMode)){ s.selectedIndex=i; break; }
  }
}

// Handler select Echelle Y
function applyYScale(){
  yScaleMode = document.getElementById('ysSelect').value;
  updateYBadge();
  redrawAll();
}

// ============================================================
// ALARM THRESHOLD
// ============================================================

// Toggle Active/Inactive checkbox
// uiInitDone ensures this choice will not be overwritten by PS
function toggleThr(){
  thrEnabled = document.getElementById('thrEnabled').checked;
  updateThrUI();
  redrawAll();
}

// Updates the visual state of the threshold controls
function updateThrUI(){
  var grp = document.getElementById('thrInputGroup');
  var leg = document.getElementById('legThr');
  var cb  = document.getElementById('thrEnabled');
  if(cb)  cb.checked = thrEnabled;
  // Grays out the controls if the threshold is disabled
  if(grp){
    grp.style.opacity      = thrEnabled ? '1'   : '.35';
    grp.style.pointerEvents= thrEnabled ? ''    : 'none';
  }
  // Dims the legend if the threshold is disabled
  if(leg) leg.style.opacity = thrEnabled ? '1' : '.25';
}

// Applies the new threshold value
function applyThr(){
  var v = parseFloat(document.getElementById('thrInput').value);
  if(isNaN(v) || v <= 0) return;
  thrVal = v;
  redrawAll();
}

// ============================================================
// POINT SIZE
// FIX v1.8: pointRadius must be an ARRAY of values
//    Chart.js v4 ignores the scalar value in dataset.pointRadius
//    when the data changes - only the array is guaranteed
// ============================================================
function updPtSize(v){
  v = parseFloat(v);
  ptSize = v;
  var lbl = document.getElementById('vPtSize');
  if(lbl) lbl.textContent = (v === 0) ? '0 (off)' : v + ' px';
  redrawAll();
}

// ============================================================
// CHART.JS PLUGIN - THRESHOLD LINES
// Drawn after the main render via afterDraw
// ============================================================
Chart.register({
  id: 'thrlines',
  afterDraw: function(chart){
    var thr = chart.config._thr;
    if(!thr) return;
    // Font adapted to the mode (compact grid vs full screen)
    var compact = chart.config._compact;
    var lblFont = compact ? 'bold 9px Consolas' : 'bold 11px Consolas';
    var c2 = chart.ctx;
    var xs = chart.scales.x;
    var ys = chart.scales.y;
    if(!xs || !ys) return;
    var yMax = ys.max || 0;
    c2.save();

    // 10M reference line (subtle gray) - always visible if within range
    try{
      var y10 = ys.getPixelForValue(10);
      if(y10 >= ys.top && y10 <= ys.bottom){
        c2.strokeStyle = gcs('--thr-gray');
        c2.lineWidth   = 1;
        c2.setLineDash([4,4]);
        c2.globalAlpha = 0.55;
        c2.beginPath(); c2.moveTo(xs.left,y10); c2.lineTo(xs.right,y10); c2.stroke();
        c2.setLineDash([]);
        c2.globalAlpha = 0.6;
        c2.fillStyle   = gcs('--thr-gray');
        c2.font        = lblFont;
        c2.fillText('10M', xs.left+3, y10-3);
      }
    }catch(e){}

    // Red threshold line - only if enabled AND within the visible range
    // v1.9: the scale is now computed to include the threshold
    //    (auto mode) -> thr.alert <= yMax is always true and the line
    //    appears simultaneously on all 4 charts.
    if(thr.enabled && thr.alert > 0 && thr.alert <= yMax){
      try{
        var yA = ys.getPixelForValue(thr.alert);
        if(yA >= ys.top && yA <= ys.bottom){
          c2.strokeStyle = gcs('--thr-red');
          c2.lineWidth   = 1.5;
          c2.setLineDash([5,3]);
          c2.globalAlpha = 0.85;
          c2.beginPath(); c2.moveTo(xs.left,yA); c2.lineTo(xs.right,yA); c2.stroke();
          c2.setLineDash([]);
          c2.globalAlpha = 1;
          c2.fillStyle   = gcs('--thr-red');
          c2.font        = lblFont;
          c2.fillText(fmb(thr.alert), xs.left+3, yA-3);
        }
      }catch(e){}
    }

    c2.restore();
  }
});

// ============================================================
// CREATE A CHART
// compact=true for the "All" view (4 charts in a 2x2 grid)
// compact=false for the individual view (full width)
// ============================================================
function makeChart(cid, compact){
  var cv = document.getElementById(cid);
  if(!cv) return null;
  var ch = new Chart(cv.getContext('2d'), {
    type: 'line',
    data: {
      labels: [],
      datasets: [
        {
          label: 'IN',
          data: [],
          borderColor:     gcs('--in-c'),
          backgroundColor: gcs('--in-f'),
          borderWidth:     compact ? 1 : 1.5,
          // Empty array - will be filled on each update
          // Chart.js v4 honors pointRadius as a per-point array
          pointRadius:     [],
          pointHoverRadius:[],
          fill: true, tension: .2, spanGaps: false
        },
        {
          label: 'OUT',
          data: [],
          borderColor:     gcs('--out-c'),
          backgroundColor: gcs('--out-f'),
          borderWidth:     compact ? 1 : 1.5,
          pointRadius:     [],
          pointHoverRadius:[],
          fill: true, tension: .2, spanGaps: false
        }
      ]
    },
    options: {
      responsive: true, maintainAspectRatio: false, animation: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: {
          title: function(items){
            if(!items || !items.length) return '';
            return ftTip(items[0].parsed.x);
          },
          label: function(c){ return c.dataset.label + ': ' + fmb(c.parsed.y); }
        }}
      },
      scales: {
        x: {
          // v1.15: LINEAR X axis with fixed time domain.
          //   The x value is real time (timestamp ms); the domain
          //   [min;max] is imposed by updateChartsForIface. Result:
          //   a partial history only occupies its fraction of the width.
          type: 'linear',
          // v1.16: X axis split into 6 EQUAL segments (7 ticks).
          //   The step is window/6 -> 10 min (Live 1h), 1 h (6h),
          //   10 h (2.5d), 60 h (15d). Same logic for all charts.
          afterBuildTicks: function(scale){
            var lo = scale.min, hi = scale.max;
            if(!isFinite(lo) || !isFinite(hi) || hi <= lo) return;
            var step = (hi - lo) / 6, arr = [];
            for(var i = 0; i <= 6; i++){ arr.push({ value: lo + i * step }); }
            scale.ticks = arr;
          },
          ticks: {
            color: gcs('--tick'),
            // Show all 7 ticks without skipping any
            autoSkip: false,
            // v1.11: hours at the same size as the rates (Y axis)
            font: { size: compact ? 9 : 12, family: 'Consolas' },
            maxRotation: 0,
            // Reformats the timestamp (ms) by the chart's view
            callback: function(value){
              var vw = (this.chart && this.chart.config && this.chart.config._view)
                       ? this.chart.config._view : 'live';
              return ft(value, vw);
            }
          },
          grid: { color: gcs('--grid') }
        },
        y: {
          min: 0,
          ticks: {
            color: gcs('--tickY'),
            // v1.9: larger font for readability
            font: { size: compact ? 9 : 12, family: 'Consolas' },
            // Fewer ticks: leaves room for 2-line labels
            maxTicksLimit: compact ? 5 : 7,
            padding: 3,
            // v1.9: multi-line label (value + unit)
            callback: yTick
          },
          grid: { color: gcs('--grid2') }
        }
      }
    }
  });
  ch.config._thr     = { alert: thrVal, enabled: thrEnabled };
  ch.config._compact = compact;
  return ch;
}

// ============================================================
// HTML PANEL INITIALIZATION
// Called on first load and when interfaces change
// ============================================================
function initPanels(ifaces){
  var t1     = document.getElementById('tabs1');
  var panels = document.getElementById('panels');
  t1.innerHTML = '';
  panels.innerHTML = '';
  charts = {};
  ifaceOrder = Object.keys(ifaces);

  ifaceOrder.forEach(function(name, idx){
    var s = sid(name);

    // Create the level 1 tab
    var tab = document.createElement('div');
    tab.className = 't1btn' + (idx === 0 ? ' a' : '');
    tab.id = 't1_' + s;
    tab.innerHTML = '<span class="t1dot"></span>' + escH(name);
    tab.onclick = (function(n){ return function(){ selectIface(n); }; })(name);
    t1.appendChild(tab);

    // Create the interface panel
    var panel = document.createElement('div');
    panel.className = 'iface-panel' + (idx === 0 ? ' a' : '');
    panel.id = 'panel_' + s;
    panel.innerHTML = buildPanelHTML(name, ifaces[name]);
    panels.appendChild(panel);

    curViews[name] = 'all';
  });

  if(ifaceOrder.length > 0) curIface = ifaceOrder[0];

  // Initialize the charts for each interface
  ifaceOrder.forEach(function(name){ initChartsForIface(name); });

  // Synchronize the Options controls
  syncYSelect();
  updateYBadge();
  updateThrUI();
  initialized = true;
}

// ============================================================
// BUILD THE HTML OF AN INTERFACE PANEL
// ============================================================
function buildPanelHTML(name, info){
  var s    = sid(name);
  var link = (info && info.link > 0) ? fmb(info.link) : '?';
  var desc = (info && info.desc) ? info.desc : '';

  // ── Barre de stats ────────────────────────────────────────
  var ibar =
    '<div class="ibar">' +
    '<div class="si"><span class="sl">&#128246;</span>' +
    '<span class="sv sn" title="'+escH(desc)+'">'+escH(name)+'</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">Link</span>' +
    '<span class="sv sn" id="link_'+s+'">'+escH(link)+'</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">&#8595; IN</span>' +
    '<span class="sv sin" id="curIn_'+s+'">--</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">&#8593; OUT</span>' +
    '<span class="sv sout" id="curOut_'+s+'">--</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">Max&#8595;</span>' +
    '<span class="sv sin" id="maxIn_'+s+'">--</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">Max&#8593;</span>' +
    '<span class="sv sout" id="maxOut_'+s+'">--</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">Avg&#8595;</span>' +
    '<span class="sv sin" id="avgIn_'+s+'">--</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">Avg&#8593;</span>' +
    '<span class="sv sout" id="avgOut_'+s+'">--</span></div>' +
    '<div class="sp"></div>' +
    '<div class="si"><span class="sl">Pts</span>' +
    '<span class="sv sn" id="pts_'+s+'">0</span></div>' +
    '</div>';

  // -- Level 2 tabs (time views) ---------------------------
  var esc = function(n){ return n.replace(/\\/g,'\\\\').replace(/'/g,"\\'"); };
  var tabs2 =
    '<div class="tabs2">' +
    '<div class="t2btn t2all a" id="t2all_'+s+'"' +
    ' onclick="selectView(\''+s+'\',\'all\',\''+esc(name)+'\')">&#9706; All</div>';
  VIEWS.forEach(function(vk){
    tabs2 +=
      '<div class="t2btn" id="t2'+vk+'_'+s+'" title="'+VLT[vk]+'"' +
      ' onclick="selectView(\''+s+'\',\''+vk+'\',\''+esc(name)+'\')">'+VL[vk]+'</div>';
  });
  tabs2 += '</div>';

  // -- Chart area: "All" view (2x2) + individual views -
  var gcont = '<div class="gcont"><div class="gall a" id="gall_'+s+'">';
  VIEWS.forEach(function(vk){
    gcont +=
      '<div class="gcell">' +
      '<div class="gclbl" title="'+VLT[vk]+'"><span>'+VL[vk]+'</span>' +
      '<span class="gclbl-s" id="cs_'+s+'_'+vk+'"></span></div>' +
      '<canvas id="c_'+s+'_'+vk+'_all"></canvas></div>';
  });
  gcont += '</div>';
  VIEWS.forEach(function(vk){
    gcont +=
      '<div class="gview" id="gv_'+s+'_'+vk+'">' +
      '<canvas id="c_'+s+'_'+vk+'_single"></canvas></div>';
  });
  gcont += '</div>';

  return ibar + tabs2 + gcont;
}

// ============================================================
// CHART INITIALIZATION FOR AN INTERFACE
// 2 charts per view (all = compact, single = full width)
// ============================================================
function initChartsForIface(name){
  var s = sid(name);
  VIEWS.forEach(function(vk){
    var ca = makeChart('c_'+s+'_'+vk+'_all',    true);
    var cs = makeChart('c_'+s+'_'+vk+'_single', false);
    if(ca) charts[s+'_'+vk+'_all']    = ca;
    if(cs) charts[s+'_'+vk+'_single'] = cs;
  });
}

// ============================================================
// SELECT AN INTERFACE (level 1 tab)
// ============================================================
function selectIface(name){
  curIface = name;
  ifaceOrder.forEach(function(n){
    var s = sid(n);
    var t = document.getElementById('t1_'+s);
    var p = document.getElementById('panel_'+s);
    if(t) t.className = 't1btn' + (n === name ? ' a' : '');
    if(p) p.className = 'iface-panel' + (n === name ? ' a' : '');
  });
}

// ============================================================
// SELECT A TIME VIEW (level 2 tab)
// ============================================================
function selectView(s, vk, name){
  // Update the level 2 tab classes
  ['all'].concat(VIEWS).forEach(function(v){
    var tb = document.getElementById('t2'+v+'_'+s);
    if(!tb) return;
    tb.className = 't2btn' + (v==='all'?' t2all':'') + (v===vk?' a':'');
  });
  // Show/hide the chart areas
  var ga = document.getElementById('gall_'+s);
  if(ga) ga.className = 'gall' + (vk==='all'?' a':'');
  VIEWS.forEach(function(v){
    var gv = document.getElementById('gv_'+s+'_'+v);
    if(gv) gv.className = 'gview' + (vk===v?' a':'');
  });
  curViews[name] = vk;
  updateChartsForIface(name);
}

// ============================================================
// UPDATE THE CHARTS OF AN INTERFACE
// Called on each 2s cycle and after every UI interaction
// ============================================================
function updateChartsForIface(name){
  if(!MD || !MD.ifaces) return;
  var s = sid(name);
  var d = MD.ifaces[name];
  if(!d) return;

  // -- PASS 1: compute the maxima -------------------------
  // globalMax    = max over the 4 views -> COMMON grid scale
  // viewMax[vk]  = max of each view   -> own scale of the full-screen view
  var globalMax = 0;
  var viewMax   = {};
  VIEWS.forEach(function(vk){
    var vd = d[vk];
    var m  = 0;
    if(vd && vd.length > 0){
      vd.forEach(function(pt){
        var vi = parseFloat(pt.i), vo = parseFloat(pt.o);
        if(vi > m) m = vi;
        if(vo > m) m = vo;
      });
    }
    viewMax[vk] = m;
    if(m > globalMax) globalMax = m;
  });

  // v1.9: the threshold PUSHES the scale (auto mode) so the line
  //    alarm is always visible. The same scale imposed on the
  //    4 cells ensures it appears everywhere simultaneously.
  var thrPush = (thrEnabled && thrVal > 0) ? thrVal : 0;

  // COMMON scale of the 4 "All" cells -> SAME height in Mbps
  var gridYMax = calcYMax(Math.max(globalMax, thrPush));

  // -- PASS 2: render each view ----------------------------
  VIEWS.forEach(function(vk){
    var vd = d[vk];
    var inD = [], outD = [];
    var mxI = 0, mxO = 0;

    // Extraction -> points {x:timestamp(ms), y:value}
    // v1.15: the x value carries real time (exact positioning).
    if(vd && vd.length > 0){
      vd.forEach(function(pt){
        var tx = parseFloat(pt.t);
        var vi = parseFloat(pt.i), vo = parseFloat(pt.o);
        inD.push({ x: tx, y: vi });
        outD.push({ x: tx, y: vo });
        if(vi > mxI) mxI = vi;
        if(vo > mxO) mxO = vo;
      });
    }

    // Full-screen view scale: its own maximum + the threshold
    var singleYMax = calcYMax(Math.max(viewMax[vk], thrPush));

    // Mini stats in the cell header ("All" view)
    var csEl = document.getElementById('cs_'+s+'_'+vk);
    if(csEl){
      csEl.textContent = '\u2193'+fmb(mxI)+' \u2191'+fmb(mxO);
    }

    // POINT SIZE FIX (v1.8):
    // Chart.js v4 requires an ARRAY of per-point values
    var n    = inD.length;
    var pts  = new Array(n);
    var ptsH = new Array(n);
    for(var k = 0; k < n; k++){
      pts[k]  = ptSize;
      ptsH[k] = ptSize + 2;
    }

    // Update the 2 charts (all + single)
    ['all','single'].forEach(function(sf){
      var ch = charts[s+'_'+vk+'_'+sf];
      if(!ch) return;
      var cp = (sf === 'all');  // compact = grid view

      // Data ({x,y}) - the X axis is time-based, no category labels
      ch.data.labels = [];

      ch.data.datasets[0].data            = inD;
      ch.data.datasets[0].borderColor     = gcs('--in-c');
      ch.data.datasets[0].backgroundColor = gcs('--in-f');
      ch.data.datasets[0].borderWidth     = cp ? 1 : 1.5;
      ch.data.datasets[0].pointRadius      = pts;
      ch.data.datasets[0].pointHoverRadius = ptsH;

      ch.data.datasets[1].data            = outD;
      ch.data.datasets[1].borderColor     = gcs('--out-c');
      ch.data.datasets[1].backgroundColor = gcs('--out-f');
      ch.data.datasets[1].borderWidth     = cp ? 1 : 1.5;
      ch.data.datasets[1].pointRadius      = pts;
      ch.data.datasets[1].pointHoverRadius = ptsH;

      // Display options (axis colors, theme, readable font)
      ch.options.scales.x.ticks.color         = gcs('--tick');
      // v1.16: the number of ticks is now imposed to 6
      //    segments (7 ticks) by afterBuildTicks in makeChart() -
      //    no more maxTicksLimit varying by view.
      // v1.11: hours at the same size as the rates (Y axis)
      ch.options.scales.x.ticks.font.size     = cp ? 9 : 12;
      ch.options.scales.x.grid.color          = gcs('--grid');

      // v1.15: FIXED X domain = [now - window ; now]
      //   -> data occupies its exact time area. A
      //   partial history leaves the left part empty instead of being
      //   stretched across the whole width.
      var winMs = VWIN[vk];
      var tMax  = Date.now();
      if(vd && vd.length){
        var lastT = parseFloat(vd[vd.length-1].t);
        if(lastT > tMax) tMax = lastT;   // safeguard if the clock is skewed
      }
      ch.options.scales.x.min = tMax - winMs;
      ch.options.scales.x.max = tMax;
      ch.config._view = vk;   // used by the X formatting callback
      ch.options.scales.y.ticks.color         = gcs('--tickY');
      // v1.9 : police Y agrandie + moins de graduations
      ch.options.scales.y.ticks.font.size     = cp ? 9 : 12;
      ch.options.scales.y.ticks.maxTicksLimit = cp ? 5 : 7;
      ch.options.scales.y.grid.color          = gcs('--grid2');

      // v1.9: common Y scale (grid) or own (full screen)
      ch.options.scales.y.max = cp ? gridYMax : singleYMax;

      // Pass the threshold state + compact mode to the plugins
      ch.config._thr     = { alert: thrVal, enabled: thrEnabled };
      ch.config._compact = cp;

      ch.update('none');
    });
  });
}

// ============================================================
// REDRAW ALL CHARTS (after theme change, etc.)
// ============================================================
function redrawAll(){
  if(!MD || !MD.ifaces) return;
  ifaceOrder.forEach(function(n){ updateChartsForIface(n); });
}

// ============================================================
// UPDATE THE STATS BAR (numeric values)
// ============================================================
function updateStats(name, d){
  var s = sid(name);
  sel('curIn_'+s,  fmb(d.curIn));
  sel('curOut_'+s, fmb(d.curOut));
  sel('maxIn_'+s,  fmb(d.maxIn));
  sel('maxOut_'+s, fmb(d.maxOut));
  sel('avgIn_'+s,  fmb(d.avgIn));
  sel('avgOut_'+s, fmb(d.avgOut));
  sel('pts_'+s,    d.samples || 0);
  if(d.link > 0) sel('link_'+s, fmb(d.link));
}

// ============================================================
// EXPORT SNAPSHOT HTML
// Generates a standalone HTML with embedded Chart.js and data
// Downloaded in the browser with a timestamp
// ============================================================
function exportSnapshot(){
  if(!MD) return;
  var now = new Date();
  var ts  = now.getFullYear() + '-' +
            ('0'+(now.getMonth()+1)).slice(-2) + '-' +
            ('0'+now.getDate()).slice(-2) + '_' +
            ('0'+now.getHours()).slice(-2) + 'h' +
            ('0'+now.getMinutes()).slice(-2);

  // Colors based on the current theme
  var bg     = darkMode ? '#1a1a2e' : '#f0f4f8';
  var tx     = darkMode ? '#e0e0e0' : '#0f1923';
  var sf     = darkMode ? '#16213e' : '#ffffff';
  var bd     = darkMode ? '#0f3460' : '#b0c0d8';
  var inC    = darkMode ? 'rgba(74,222,128,.9)'  : 'rgba(0,140,80,.9)';
  var inF    = darkMode ? 'rgba(74,222,128,.12)' : 'rgba(0,180,100,.10)';
  var outC   = darkMode ? 'rgba(76,201,240,.9)'  : 'rgba(0,99,190,.9)';
  var outF   = darkMode ? 'rgba(76,201,240,.10)' : 'rgba(0,99,190,.08)';
  var titleC = darkMode ? '#4cc9f0' : '#0063be';

  // Retrieve the Chart.js code embedded in the page
  var chartSrc = '';
  try{
    var sc = document.getElementsByTagName('script');
    for(var i=0; i<sc.length; i++){
      if(sc[i].innerHTML.length > 50000){ chartSrc = sc[i].innerHTML; break; }
    }
  }catch(e){}

  var nowStr = new Date().toLocaleString('en-US');

  // Build the snapshot HTML
  var html =
    '<!DOCTYPE html><html><head><meta charset="UTF-8">' +
    '<title>PS-MRTG Snapshot ' + ts + '</title>' +
    (chartSrc
      ? '<script>' + chartSrc + '<\/script>'
      : '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"><\/script>'
    ) +
    '<style>' +
    'body{background:'+bg+';color:'+tx+';font-family:Segoe UI,monospace;padding:16px;margin:0}' +
    'h2{margin-bottom:4px}.sub{color:#778899;font-size:.8em;margin-bottom:14px}' +
    '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(460px,1fr));gap:12px}' +
    '.card{background:'+sf+';border:1px solid '+bd+';border-radius:8px;padding:12px}' +
    '.ct{font-size:.9em;font-weight:bold;color:'+titleC+';margin-bottom:6px}' +
    '.st{display:flex;gap:12px;font-size:.76em;margin-bottom:8px;flex-wrap:wrap}' +
    '</style></head><body>' +
    '<h2>&#128247; PS-MRTG Snapshot</h2>' +
    '<div class="sub">' + nowStr + ' &mdash; ' + escH(MD.dur||'') + '</div>' +
    '<div class="grid" id="g"></div>' +
    // Snapshot chart rendering script
    '<script>var D=' + JSON.stringify(MD) + ';' +
    'var ST=[10,100,1000,10000,100000,200000];' +
    'function fmb(v){v=parseFloat(v);if(isNaN(v)||v<0)return"--";' +
    'if(v===0)return"0 Kbps";if(v>=1000)return(v/1000).toFixed(2)+" Gbps";' +
    'if(v>=1)return v.toFixed(2)+" Mbps";return(v*1000).toFixed(0)+" Kbps";}' +
    'function yt(v){v=parseFloat(v);if(isNaN(v)||v<0)return"";if(v===0)return"0";' +
    'if(v>=1000){var g=v/1000;return[(g%1===0?String(g):g.toFixed(2).replace(/0+$/,"").replace(/\\.$/,"")),"Gbps"];}' +
    'if(v>=1)return[(v%1===0?String(v):v.toFixed(1)),"Mbps"];' +
    'return[String(Math.round(v*1000)),"Kbps"];}' +
    'function ft(ms){var n=parseInt(ms,10);if(isNaN(n)||n<=0)return"";' +
    'var d=new Date(n);return("0"+d.getHours()).slice(-2)+":"' +
    '+("0"+d.getMinutes()).slice(-2)+":"+("0"+d.getSeconds()).slice(-2);}' +
    'window.addEventListener("load",function(){' +
    'if(!window.Chart||!D)return;' +
    'var g=document.getElementById("g");' +
    'Object.keys(D.ifaces).forEach(function(nm){' +
    'var d=D.ifaces[nm];' +
    'var card=document.createElement("div");card.className="card";' +
    'var sn=nm.replace(/[^a-zA-Z0-9]/g,"_");' +
    'card.innerHTML=' +
    '"<div class=ct>"+nm+"</div>' +
    '<div class=st>' +
    '<span style=\'color:'+inC+'\'>&#8595; "+fmb(d.curIn)+"</span>' +
    '<span style=\'color:'+outC+'\'>&#8593; "+fmb(d.curOut)+"</span>' +
    '<span>Max&#8595; "+fmb(d.maxIn)+"</span>' +
    '<span>Max&#8593; "+fmb(d.maxOut)+"</span>' +
    '</div><canvas id=\'c_"+sn+"\' height=\'110\'></canvas>";' +
    'g.appendChild(card);' +
    'var vd=d.live;if(!vd||!vd.length)return;' +
    'var lb=[],ins=[],outs=[];' +
    'vd.forEach(function(p){lb.push(ft(p.t));ins.push(parseFloat(p.i));outs.push(parseFloat(p.o));});' +
    'var mx=0;ins.forEach(function(v){if(v>mx)mx=v;});outs.forEach(function(v){if(v>mx)mx=v;});' +
    'var ym=ST[ST.length-1];' +
    'for(var i=0;i<ST.length;i++){if(mx<=ST[i]){ym=ST[i];break;}}' +
    'var cv=document.getElementById("c_"+sn);if(!cv)return;' +
    'new Chart(cv.getContext("2d"),{type:"line",' +
    'data:{labels:lb,datasets:[' +
    '{label:"IN",data:ins,borderColor:"'+inC+'",backgroundColor:"'+inF+'",' +
    'borderWidth:1.5,pointRadius:1,fill:true,tension:.2},' +
    '{label:"OUT",data:outs,borderColor:"'+outC+'",backgroundColor:"'+outF+'",' +
    'borderWidth:1.5,pointRadius:1,fill:true,tension:.2}' +
    ']},' +
    'options:{responsive:true,maintainAspectRatio:false,animation:false,' +
    'plugins:{legend:{display:false}},' +
    'scales:{x:{ticks:{maxTicksLimit:6,font:{size:11}}},' +
    'y:{min:0,max:ym,ticks:{font:{size:11},maxTicksLimit:6,padding:3,callback:function(v){return yt(v);}}}}}});' +
    '});});' +
    '<\/script></body></html>';

  // Download the snapshot
  var blob = new Blob([html], {type:'text/html;charset=utf-8'});
  var url  = URL.createObjectURL(blob);
  var a    = document.createElement('a');
  a.href     = url;
  a.download = 'PSMrtg_Snapshot_' + ts + '.html';
  a.click();
  setTimeout(function(){ URL.revokeObjectURL(url); }, 2000);
}

// ============================================================
// DATA LOADING (2s cycle)
// Reloads network_data.js which defines window.MD
// ============================================================
function loadData(){
  // Remove the previous script to force a reload
  var old = document.getElementById('_mds');
  if(old && old.parentNode) old.parentNode.removeChild(old);

  var s = document.createElement('script');
  s.id  = '_mds';
  s.src = DJP + '?_=' + Date.now();  // Cache-busting

  s.onload = function(){
    if(!window.MD) return;
    MD = window.MD;

    // ONE-TIME INIT from PS - never overwritten afterwards
    // thrEnabled, thrVal, yScaleMode: controlled by the UI after init
    if(!uiInitDone){
      thrVal     = MD.threshold     || thrVal;
      thrEnabled = (MD.thresholdEnabled !== undefined)
                    ? MD.thresholdEnabled : thrEnabled;
      if(MD.yScaleMode !== undefined) yScaleMode = String(MD.yScaleMode);
      // Synchronize the visual controls
      var cb = document.getElementById('thrEnabled');
      if(cb) cb.checked = thrEnabled;
      var ti = document.getElementById('thrInput');
      if(ti) ti.value = thrVal;
      syncYSelect();
      updateYBadge();
      updateThrUI();
      uiInitDone = true;
    }

    // Update header (time + duration)
    sel('durLbl', MD.dur || '--');
    sel('nowLbl', MD.now || '--:--:--');

    // Rebuild panels if the interfaces have changed
    var ni = Object.keys(MD.ifaces);
    if(!initialized ||
       JSON.stringify(ni.slice().sort()) !==
       JSON.stringify(ifaceOrder.slice().sort())){
      initPanels(MD.ifaces);
    }

    // Update stats + charts for each interface
    ni.forEach(function(name){
      if(MD.ifaces[name]){
        updateStats(name, MD.ifaces[name]);
        updateChartsForIface(name);
      }
    });
  };

  s.onerror = function(){};
  document.head.appendChild(s);
}

// Startup: first load then 2s cycle
loadData();
setInterval(loadData, 2000);
</script>
</body>
</html>
"@
    try {
        $html | Set-Content -Path $htmlFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host "  ERREUR ecriture HTML : $_" -ForegroundColor Red
    }
}

# ============================================================
# SECTION 19 - MAIN ENTRY POINT
# ============================================================
$script:startMs = Get-NowMs

# Startup banner
Write-Host ""
Write-Host "  Mode : $($ExecutionContext.SessionState.LanguageMode)" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "   PS-MRTG v1.22 - MRTG Bandwidth Monitor"                  -ForegroundColor White
Write-Host "   Network bandwidth - real time"          -ForegroundColor Yellow
Write-Host "   Interval   : ${IntervalSec}s | MaxPts : $MaxPoints" -ForegroundColor Yellow
Write-Host "   Y scale  : $YScaleMode"                    -ForegroundColor Yellow
Write-Host "   Threshold  : $ThresholdAlertMbps Mbps (active:$ThresholdEnabled)" `
           -ForegroundColor Yellow
Write-Host "   Report     : $htmlFile"                      -ForegroundColor Gray
Write-Host "   Stop       : Ctrl+C"                         -ForegroundColor Red
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host ""

# -- Interface detection --------------------------------------
Write-Host "  Detecting active interfaces..." -ForegroundColor Cyan
$script:ActiveIfaces = Get-ActiveInterfaces
if ($script:ActiveIfaces.Count -eq 0) {
    Write-Host "  WARNING : No interface detected !" -ForegroundColor Red
} else {
    Write-Host "  $($script:ActiveIfaces.Count) interface(s) detected." `
               -ForegroundColor Green
}
Write-Host ""

# -- Buffer initialization -----------------------------------
foreach ($ifName in $script:ActiveIfaces.Keys) {
    Init-InterfaceBuffers -Name $ifName
}

# -- Counter debug (shown once at startup) --------------------
Debug-Counters

# -- Raw counter initialization (first poll) ----------------
Write-Host "  Initializing counters..." -ForegroundColor Cyan
$initCounters = Get-NetworkCounters
$initMs       = Get-NowMs
foreach ($ifName in $script:interfaces.Keys) {
    $info = $script:ActiveIfaces[$ifName]
    $desc = if ($null -ne $info) { "$($info.Description)" } else { "" }
    $cKey = Find-CounterKey -IfaceName $ifName -IfaceDesc $desc -Counters $initCounters
    if ($null -ne $cKey) {
        $script:rawCounters[$ifName].LastIn  = [long]$initCounters[$cKey].BytesIn
        $script:rawCounters[$ifName].LastOut = [long]$initCounters[$cKey].BytesOut
        $script:rawCounters[$ifName].LastTs  = $initMs
        Write-Host "  Init OK : '$ifName' -> '$cKey'" -ForegroundColor Green
    } else {
        Write-Host "  Init FAIL : '$ifName' - counter not found" -ForegroundColor Red
    }
}
Write-Host ""

# -- HTML generation + first data.js write --------------------
Write-HtmlOnce
Write-DataJs

# -- Open the browser -----------------------------------------
$script:browserProc = Open-Browser -FilePath $htmlFile
Write-Host "  Browser opened." -ForegroundColor Green
if ($script:browserProc) {
    Write-Host "  Auto-stop : active (close the window to stop)" -ForegroundColor Gray
} else {
    Write-Host "  Auto-stop : inactive (browser not monitorable)" -ForegroundColor Gray
}
Write-Host "  Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

# ── Boucle principale ────────────────────────────────────────
$lastWrite   = Get-Date
$lastCollect = Get-Date
$lastAlive   = Get-Date
$startWatch  = Get-Date
$AliveEvery  = 5     # seconds between two window checks
$WatchGrace  = 12    # grace (s): give the browser time to spawn its process
$wasAlive    = $false  # true once the dashboard window is confirmed open
$missStreak  = 0     # consecutive checks with no browser -> closed

try {
    while ($true) {

        # --- Window watch (auto-stop), v1.22 ---
        # Detect the dashboard window via ANY browser process using our
        # dedicated profile dir (robust to Edge/Chrome launcher hand-off,
        # which made the old PID-based watch unreliable). Stop once the
        # window was confirmed open AND then absent on 2 consecutive checks.
        if (((Get-Date) - $startWatch).TotalSeconds -ge $WatchGrace) {
            if (((Get-Date) - $lastAlive).TotalSeconds -ge $AliveEvery) {
                $lastAlive = Get-Date
                if (Test-BrowserOpen -ProfileDir $profileDir) {
                    $wasAlive = $true; $missStreak = 0
                } elseif ($wasAlive) {
                    $missStreak++
                    if ($missStreak -ge 2) {
                        Write-Host "  Window closed -> automatic stop." -ForegroundColor Yellow
                        break
                    }
                }
            }
        }

        $now = Get-Date

        # Read browser commands (threshold, yScale)
        Read-CmdFile

        # Collect bandwidth (every $IntervalSec s)
        if (($now - $lastCollect).TotalSeconds -ge $IntervalSec) {
            Collect-Bandwidth
            $lastCollect = $now
        }

        # Write network_data.js (every $WriteEvery s)
        if (($now - $lastWrite).TotalSeconds -ge $WriteEvery) {
            Write-DataJs
            $lastWrite = $now

            # Console log: duration + current rates per interface
            $elapsed = Get-ElapsedSec
            $hh = [int]($elapsed / 3600)
            $mm = [int](($elapsed % 3600) / 60)
            $ss = $elapsed % 60
            $parts = @()
            foreach ($ifName in $script:interfaces.Keys) {
                $iface  = $script:interfaces[$ifName]
                $parts += "$ifName  IN:$(Format-Mbps $iface.CurIn)  OUT:$(Format-Mbps $iface.CurOut)"
            }
            Write-Host ("  [{0:D2}h{1:D2}m{2:D2}s]  {3}" -f `
                $hh, $mm, $ss, ($parts -join "   |   ")) -ForegroundColor Cyan
        }

        # Short pause to avoid saturating the CPU
        Start-Sleep -Milliseconds 200
    }
}
finally {
    # Block executed even on Ctrl+C
    Write-Host ""
    Write-Host "  Stopping PS-MRTG..." -ForegroundColor Yellow
    Write-DataJs   # Final data flush
    Write-Host "  Final report : $htmlFile" -ForegroundColor Gray
    # Release single-instance lock and close our own browser window if it
    # is still open (e.g. on Ctrl+C), so nothing is left orphaned.
    Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
    try {
        Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -like "*$profileDir*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    Write-Host "  Stopped." -ForegroundColor Green
    Write-Host ""
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
