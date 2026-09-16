# skin-lib.ps1 - shared library for MonkeyCode Skin MVP (ASCII only, PS 5.1)
# Dot-source this file: . "$PSScriptRoot\skin-lib.ps1"

$script:MC_EXE_DEFAULT = 'D:\MonkeyCode\monkeycode-desktop.exe'
$script:MC_PROC_NAME   = 'monkeycode-desktop'
$script:MC_CT          = [System.Threading.CancellationToken]::None

# Reference tuning profile (derived from the approved cecilylove002 look).
# Applied at inject time to EVERY theme (built-in / imported / gallery download)
# so every pack gets the same "wallpaper is the hero" treatment; theme pack
# files are never modified.
$script:MC_TUNING = @{
    SurfaceOpacity = 0.5    # panels 50% translucent -> wallpaper stays clearly visible
    BlurPx         = 0      # no wallpaper blur
    Fit            = 'cover'
    WallpaperTint  = 0.25   # theme base-300 tint laid over the photo (reference recipe)
    WallpaperSat   = 0.9    # photo saturation (reference recipe)
}

function Write-McLog {
    param([string]$Path, [string]$Message, [switch]$NoHost)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
    Add-Content -Path $Path -Value $line -Encoding UTF8
    # NoHost: ps2exe -noConsole pops Write-Host from dispatcher callbacks as MessageBoxes
    if (-not $NoHost) { Write-Host $line }
}

function Stop-MonkeyApp {
    param([string]$ProcName)
    if (-not $ProcName) { $ProcName = $script:MC_PROC_NAME }
    # Close MonkeyCode gracefully, then force. Also clear webview processes holding the profile lock.
    $procs = Get-Process $ProcName -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }
    foreach ($p in $procs) { [void]$p.CloseMainWindow() }
    [void](Wait-Process -Name $ProcName -Timeout 5 -ErrorAction SilentlyContinue)
    $left = Get-Process $ProcName -ErrorAction SilentlyContinue
    if ($left) { $left | Stop-Process -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 3
    $wv = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue |
          Where-Object { $_.CommandLine -match 'monkeycode' }
    if ($wv) { $wv | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
    Start-Sleep -Seconds 2
    return $true
}

function Start-MonkeyAppWithCdp {
    param([int]$Port = 9223, [string]$AppExe = $script:MC_EXE_DEFAULT)
    if (-not (Test-Path $AppExe)) { throw "MonkeyCode exe not found: $AppExe" }
    # Session-only env var: affects only the child process we spawn, never persists.
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"
    Start-Process -FilePath $AppExe -WorkingDirectory (Split-Path $AppExe)
    Start-Sleep -Milliseconds 500
    $procName = [IO.Path]::GetFileNameWithoutExtension($AppExe)
    return (Get-Process $procName -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id)
}

# Locate the MonkeyCode desktop exe on any machine: config choice -> running
# process -> well-known folders -> registry uninstall entries. Returns $null if all fail.
function Resolve-MonkeyExe {
    param([string]$Configured, [string[]]$Roots = @('D:\MonkeyCode', 'C:\MonkeyCode', "$env:LOCALAPPDATA\Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)}))
    if ($Configured -and (Test-Path $Configured)) { return $Configured }
    try {
        $p = Get-Process $script:MC_PROC_NAME -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
        if ($p -and $p.Path) { return $p.Path }
    } catch { }
    foreach ($r in $Roots) {
        if (-not $r -or -not (Test-Path $r)) { continue }
        try {
            $hit = Get-ChildItem $r -Filter 'monkeycode-desktop.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch { }
    }
    foreach ($k in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        try {
            $rows = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*MonkeyCode*' }
            foreach ($row in $rows) {
                $loc = if ($row.InstallLocation) { ([string]$row.InstallLocation).Trim('"').Trim() } else { $null }
                if ($loc) {
                    $cand = Join-Path $loc 'monkeycode-desktop.exe'
                    if (Test-Path $cand) { return $cand }
                }
                $icon = if ($row.DisplayIcon) { ([string]$row.DisplayIcon).Trim('"') -replace ',\d+$', '' } else { $null }
                if ($icon -and ($icon -like '*.exe') -and (Test-Path $icon)) { return $icon }
            }
        } catch { }
    }
    return $null
}

function Wait-CdpOpen {
    param([int]$Port = 9223, [int]$TimeoutSec = 30)
    for ($i = 1; $i -le $TimeoutSec; $i++) {
        Start-Sleep -Seconds 1
        try {
            $v = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
            return $v
        } catch { }
    }
    return $null
}

# ---------- minimal CDP-over-WebSocket client (verified in PoC) ----------

function Connect-CdpWs {
    param([string]$WsUrl)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    [void]$ws.ConnectAsync([Uri]$WsUrl, $script:MC_CT).Wait(8000)
    if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        $st = $ws.State; $ws.Dispose(); throw "WS connect failed: $st"
    }
    return $ws
}

function Disconnect-CdpWs {
    param($Ws)
    try {
        if ($Ws -and $Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            [void]$Ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $script:MC_CT).Wait(2000)
        }
    } catch { }
    if ($Ws) { $Ws.Dispose() }
}

function Send-CdpJson {
    param($Ws, $Obj)
    $b = [Text.Encoding]::UTF8.GetBytes(($Obj | ConvertTo-Json -Depth 8 -Compress))
    [void]$Ws.SendAsync([ArraySegment[byte]]::new($b), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $script:MC_CT).Wait(10000)
}

function Receive-CdpMsg {
    param($Ws, [int]$TimeoutMs = 15000)
    $buf = New-Object byte[] 4194304
    $ms  = New-Object System.IO.MemoryStream
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $t = $Ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $script:MC_CT)
        if (-not $t.Wait(2000)) { continue }
        $r = $t.Result
        if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw 'ws closed by peer' }
        $ms.Write($buf, 0, $r.Count)
        if ($r.EndOfMessage) {
            $s = [Text.Encoding]::UTF8.GetString($ms.ToArray()); $ms.SetLength(0); return $s
        }
    }
    throw 'recv timeout'
}

function Invoke-Cdp {
    param($Ws, [int]$Id, [string]$Method, $Params)
    Send-CdpJson -Ws $Ws -Obj @{ id = $Id; method = $Method; params = $Params }
    $want = '"id":' + $Id + '\b'
    while ($true) {
        $m = Receive-CdpMsg -Ws $Ws -TimeoutMs 20000
        if ($m -match $want) { return $m }
    }
}

function Get-CdpPageTargets {
    param([int]$Port = 9223)
    $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 3
    return @($targets | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })
}

# ---------- theme pack ----------

function Get-ThemePack {
    param([string]$ThemeDir)
    $jsonPath = Join-Path $ThemeDir 'theme.json'
    if (-not (Test-Path $jsonPath)) { throw "theme.json not found in $ThemeDir" }
    $meta = [IO.File]::ReadAllText($jsonPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

    $bgPath = $null
    foreach ($ext in '.jpg', '.jpeg', '.png', '.webp') {
        $cand = Join-Path $ThemeDir ("background" + $ext)
        if (Test-Path $cand) { $bgPath = $cand; break }
    }
    $cssPath = Join-Path $ThemeDir 'theme.css'
    $css = ''
    if (Test-Path $cssPath) { $css = [IO.File]::ReadAllText($cssPath, [Text.Encoding]::UTF8) }

    return @{
        Meta    = $meta
        BgPath  = $bgPath
        Css     = $css
        Name    = $meta.id
        Version = [string]$meta.version
    }
}

function New-SkinBootstrapJs {
    # Build the injected bootstrap. It mimics MonkeyCode's own background feature
    # (activates html[data-mc-background=active]), then applies ALL skin variables
    # and theme.css via an injected <style> with !important, so the app's own
    # preference code (which rewrites inline vars without !important) can never
    # override the skin. Idempotent: safe to run on every new document.
    # The (potentially huge) wallpaper data-URI is embedded as a raw single-quoted
    # JS string (base64 is JS-string-safe), so ConvertTo-Json only ever handles
    # the small CSS part - keeps import/push fast for multi-MB wallpapers.
    param($ThemePack, $Tuning)
    $tun = if ($Tuning) { $Tuning } else { $script:MC_TUNING }
    $meta = $ThemePack.Meta
    # apply-time tuning overrides the pack's look params (pack files stay untouched)
    $opacity = [double]($(if ($null -ne $tun.SurfaceOpacity) { $tun.SurfaceOpacity } else { $meta.surfaceOpacity }))
    $opacityPct = [int]($opacity * 100)
    $blurPx     = [string]($(if ($null -ne $tun.BlurPx) { $tun.BlurPx } else { $meta.blurPx }))
    if (-not $blurPx) { $blurPx = '0' }
    $fit        = [string]($(if ($null -ne $tun.Fit) { $tun.Fit } else { $meta.fit }))
    if (-not $fit) { $fit = 'cover' }
    $pos = [string]$meta.position
    if (-not $pos) { $pos = 'center' }

    $bgExpr = 'null'
    $imgExpr = 'null'
    $paintExpr = 'null'
    $varsCss = @"
html[data-mc-background=`"active`"]{
  --mc-background-size:$fit !important;
  --mc-background-repeat:no-repeat !important;
  --mc-background-position:$pos !important;
  --mc-background-blur:$($blurPx)px !important;
  --mc-surface-opacity:$opacityPct% !important;
}
"@
    # Reference wallpaper treatment: if the pack's own CSS does not paint the
    # wallpaper layer (.mc-workbench-background), apply the approved reference
    # recipe at inject time - this is what actually makes the photo visible.
    $needsTreatment = $ThemePack.Css -notmatch '\.mc-workbench-background'
    $tint = '0,0,0'
    if ($needsTreatment -and $ThemePack.Css -match '--color-base-300:\s*#([0-9a-fA-F]{6})\s*;') {
        $h = $Matches[1]
        $tint = '{0},{1},{2}' -f [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
    }
    $tintA = [string]$tun.WallpaperTint
    $sat = [string]$tun.WallpaperSat

    if ($ThemePack.BgPath) {
        $mime = @{ '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.png' = 'image/png'; '.webp' = 'image/webp' }[[IO.Path]::GetExtension($ThemePack.BgPath).ToLower()]
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ThemePack.BgPath))
        $dataUrl = 'data:' + $mime + ';base64,' + $b64
        # raw CSS rules embedded as JS single-quoted strings; base64 contains no quote chars
        $imgExpr = "'" + 'html[data-mc-background="active"]{--mc-background-image:url("' + $dataUrl + '") !important;}' + "'"
        if ($needsTreatment) {
            # Paint the wallpaper layer DIRECTLY with the url (normal declaration):
            # Chromium caps custom property values at 2^21 chars (verified in-page:
            # 2,000,000 OK / 2,100,000 dropped), so wallpapers whose data-URI is
            # larger silently fall out of var(--mc-background-image).
            $paintCss = 'html[data-mc-background="active"] .mc-workbench-background{background-image:linear-gradient(rgba(' + $tint + ',' + $tintA + '), rgba(' + $tint + ',' + $tintA + ')), url("' + $dataUrl + '") !important;filter:saturate(' + $sat + ') blur(var(--mc-background-blur, 0px));}'
            $paintExpr = "'" + $paintCss + "'"
        }
        $bgExpr = 'true'
    }

    $cssAll = $ThemePack.Css
    if ($needsTreatment -and -not $ThemePack.BgPath) {
        # no wallpaper image in the pack: var-based gradient-only fallback
        $cssAll = $ThemePack.Css + "`n" + @"
/* auto-tuned wallpaper treatment (reference profile, injected at apply time) */
html[data-mc-background="active"] .mc-workbench-background{
  background-image: linear-gradient(rgba($tint,$tintA), rgba($tint,$tintA)), var(--mc-background-image);
  filter: saturate($sat) blur(var(--mc-background-blur, 0px));
}
"@
    }

    $cssJson = ($varsCss + "`n" + $cssAll) | ConvertTo-Json -Compress

    return @"
(function(){
try{
  var t=document.documentElement;
  var OLD=document.getElementById('mc-skin-style'); if(OLD) OLD.remove();
  if($bgExpr){ t.setAttribute('data-mc-background','active'); } else { t.removeAttribute('data-mc-background'); }
  var css=$cssJson;
  var IMG=$imgExpr;
  if(IMG){ css+=`"\n`"+IMG; }
  var PAINT=$paintExpr;
  if(PAINT){ css+=`"\n`"+PAINT; }
  var s=document.createElement('style'); s.id='mc-skin-style'; s.textContent=css;
  (document.head||document.documentElement).appendChild(s);
  window.__MC_SKIN='$([string]$meta.id)@$([string]$meta.version)';
}catch(e){}
})()
"@
}

function Push-ThemeToTarget {
    param($Target, $BootstrapJs, $LogPath)
    try {
        $ws = Connect-CdpWs -WsUrl $Target.webSocketDebuggerUrl
        try {
            [void](Invoke-Cdp -Ws $ws -Id 1 -Method 'Runtime.enable' -Params @{})
            [void](Invoke-Cdp -Ws $ws -Id 2 -Method 'Page.enable' -Params @{})
            $r1 = Invoke-Cdp -Ws $ws -Id 3 -Method 'Runtime.evaluate' -Params @{ expression = $BootstrapJs; returnByValue = $true }
            if ($r1 -match '"subtype":"error"') {
                Write-McLog -Path $LogPath -Message ("APPLY ERROR -> {0} : {1}" -f $Target.url, $r1.Substring(0, [Math]::Min(200, $r1.Length)))
                return $false
            }
            $r2 = Invoke-Cdp -Ws $ws -Id 4 -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $BootstrapJs }
            Write-McLog -Path $LogPath -Message ("THEME OK -> {0} | apply={1}" -f $Target.url, $r1.Substring(0, [Math]::Min(80, $r1.Length)))
            return $true
        } finally { Disconnect-CdpWs -Ws $ws }
    } catch {
        Write-McLog -Path $LogPath -Message ("THEME FAIL -> {0} : {1}" -f $Target.url, $_.Exception.Message)
        return $false
    }
}

# ---------- Codex Dream Skin theme pack import ----------

function Read-ZipEntryBytes {
    param($Entry)
    $ms = New-Object IO.MemoryStream
    $s = $Entry.Open()
    try { $s.CopyTo($ms) } finally { $s.Dispose() }
    , $ms.ToArray()
}

function Read-ZipEntryText {
    param($Entry)
    [Text.Encoding]::UTF8.GetString((Read-ZipEntryBytes -Entry $Entry))
}

function New-MonkeyCssFromCodexColors {
    # Map Codex Dream Skin color tokens to MonkeyCode (daisyUI) palette vars.
    param($Colors)
    function HexOk([string]$h) { $h -match '^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$' }
    function HexStrip([string]$h) { if ($h -match '^#[0-9a-fA-F]{8}$') { $h.Substring(0, 7) } else { $h } }
    $pairs = @(
        @('background', '--color-base-300'),
        @('panel', '--color-base-100'),
        @('panelAlt', '--color-base-200'),
        @('accent', '--color-primary'),
        @('accentAlt', '--color-accent'),
        @('secondary', '--color-secondary'),
        @('highlight', '--color-info'),
        @('text', '--color-base-content'),
        @('line', '--color-neutral')
    )
    $lines = @('/* generated by MonkeyCode Skin from a Codex Dream Skin package */', 'html[data-mc-background="active"]{')
    foreach ($p in $pairs) {
        $h = ''
        if ($Colors) { $h = [string]$Colors.($p[0]) }
        if ($h -and (HexOk $h)) { $lines += ('  ' + $p[1] + ':' + (HexStrip $h) + ';') }
    }
    $lines += '}'
    (($lines -join "`r`n") + "`r`n")
}

function Import-CodexThemePack {
    # Import a Codex Dream Skin theme package (zip) into themes\<id>\.
    # Supports manifest packs (packageVersion 1, sha256 verified) and simplified
    # local zips (theme.json + optional theme.css + background image). Mirrors the
    # Dream Skin contract limits: zip <=32 MiB, <=32 entries, <=64 MiB extracted.
    # Files may sit at zip root or inside a single top-level directory.
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$ThemesRoot,
        [switch]$Force
    )
    if (-not (Test-Path $ZipPath)) { throw ("zip not found: " + $ZipPath) }
    $zipLen = (Get-Item $ZipPath).Length
    if ($zipLen -gt 32MB) { throw ("zip larger than 32 MiB: " + $zipLen) }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($zip.Entries.Count -gt 32) { throw ("zip has more than 32 entries: " + $zip.Entries.Count) }
        $sum = ($zip.Entries | Measure-Object -Property Length -Sum).Sum
        if ($sum -gt 64MB) { throw ("extracted content larger than 64 MiB: " + $sum) }
        foreach ($e in $zip.Entries) {
            if ($e.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or $e.FullName -match '^[A-Za-z]:') { throw ("unsafe entry path: " + $e.FullName) }
        }

        # locate theme.json (zip root or single top-level directory)
        $prefix = ''
        $themeEntry = $zip.Entries | Where-Object { $_.FullName -eq 'theme.json' } | Select-Object -First 1
        if (-not $themeEntry) {
            $cands = @($zip.Entries | Where-Object { $_.FullName -match '^[^/\\]+[/\\]theme\.json$' })
            if ($cands.Count -gt 0) {
                $themeEntry = $cands[0]
                $prefix = $themeEntry.FullName.Substring(0, $themeEntry.FullName.Length - 'theme.json'.Length)
            }
        }
        if (-not $themeEntry) { throw 'theme.json not found (zip root or single subdir)' }

        function FindZip([string]$name) {
            $e = $zip.Entries | Where-Object { $_.FullName -eq ($prefix + $name) } | Select-Object -First 1
            if (-not $e -and $prefix) { $e = $zip.Entries | Where-Object { $_.FullName -eq $name } | Select-Object -First 1 }
            return $e
        }

        $t = (Read-ZipEntryText -Entry $themeEntry) | ConvertFrom-Json
        $id = [string]$t.id
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { throw ("invalid or missing theme id: " + $id) }
        $imageName = [string]$t.image
        if (-not $imageName) { throw 'theme.json has no image field' }
        $imgExt = [IO.Path]::GetExtension($imageName).ToLower()
        if ('.jpg', '.jpeg', '.png', '.webp' -notcontains $imgExt) { throw ("unsupported background image type: " + $imgExt) }
        $imgEntry = FindZip $imageName
        if (-not $imgEntry) { throw ("background image entry not found: " + $imageName) }

        # integrity: verify sha256 for every file listed in manifest.json (if present)
        $manifest = $null
        $manEntry = FindZip 'manifest.json'
        if ($manEntry) {
            $manifest = (Read-ZipEntryText -Entry $manEntry) | ConvertFrom-Json
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                foreach ($f in $manifest.files) {
                    $fe = FindZip ([string]$f.path)
                    if (-not $fe) { throw ("manifest lists missing file: " + $f.path) }
                    $hash = [BitConverter]::ToString($sha.ComputeHash((Read-ZipEntryBytes -Entry $fe))).Replace('-', '').ToLower()
                    if ($hash -ne ([string]$f.sha256).ToLower()) { throw ("sha256 mismatch: " + $f.path) }
                }
            } finally { $sha.Dispose() }
        }

        $dest = Join-Path $ThemesRoot $id
        if ((Test-Path $dest) -and -not $Force) { throw ("theme dir already exists: " + $dest + " (use -Force to overwrite)") }
        New-Item $dest -ItemType Directory -Force | Out-Null
        $utf8 = New-Object Text.UTF8Encoding($false)

        $bgName = 'background' + $imgExt
        [IO.File]::WriteAllBytes((Join-Path $dest $bgName), (Read-ZipEntryBytes -Entry $imgEntry))

        # original Codex theme.css targets Codex DOM ([data-ds-part=...]); keep for
        # reference but do NOT inject (selectors are meaningless inside MonkeyCode)
        $cssEntry = FindZip 'theme.css'
        if ($cssEntry) {
            $orig = Read-ZipEntryText -Entry $cssEntry
            if ($orig.Trim()) { [IO.File]::WriteAllText((Join-Path $dest 'codex-extra.css'), $orig, $utf8) }
        }

        # surface opacity: honor the author's panel alpha (e.g. #1e1e1e55 -> 0.33)
        $opacity = 0.72
        $panelHex = ''
        if ($t.colors) { $panelHex = [string]$t.colors.panel }
        if ($panelHex -match '^#[0-9a-fA-F]{8}$') {
            $a = [Convert]::ToInt32($panelHex.Substring(7, 2), 16) / 255.0
            if ($a -ge 0.10 -and $a -le 1.0) { $opacity = [math]::Round($a, 2) }
        }
        # focus point -> background-position percentage
        $fx = 0.5; $fy = 0.5
        if ($t.art) {
            if ($null -ne $t.art.focusX) { $fx = [double]$t.art.focusX }
            if ($null -ne $t.art.focusY) { $fy = [double]$t.art.focusY }
        }
        $pos = ('{0}%' -f [int][math]::Round($fx * 100)) + ' ' + ('{0}%' -f [int][math]::Round($fy * 100))

        $meta = [ordered]@{
            id             = $id
            name           = [string]$t.name
            version        = $(if ($manifest) { [string]$manifest.version } else { '0.0.0' })
            appearance     = [string]$t.appearance
            surfaceOpacity = $opacity
            blurPx         = 0
            fit            = 'cover'
            position       = $pos
            background     = $bgName
            imported       = [ordered]@{
                source     = 'codex-dream-skin'
                license    = $(if ($manifest -and $manifest.license) { [string]$manifest.license } else { '' })
                publisher  = $(if ($manifest -and $manifest.publisher) { [string]$manifest.publisher.displayName } else { '' })
                importedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
        }
        [IO.File]::WriteAllText((Join-Path $dest 'theme.json'), ($meta | ConvertTo-Json -Depth 5), $utf8)
        [IO.File]::WriteAllText((Join-Path $dest 'theme.css'), (New-MonkeyCssFromCodexColors -Colors $t.colors), $utf8)

        $lic = ''
        if ($manifest -and $manifest.license) { $lic = [string]$manifest.license }
        return @{ Id = $id; Name = [string]$t.name; Dir = $dest; SurfaceOpacity = $opacity; Verified = [bool]$manifest; License = $lic }
    } finally { $zip.Dispose() }
}
