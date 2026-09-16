# skin-injector.ps1 - MonkeyCode Skin injector (ASCII only, PS 5.1)
# Pushes the theme into every page target via CDP, then watches for new targets.
# Exits automatically when MonkeyCode exits.
param(
    [string]$Theme = 'aurora',
    [int]$Port = 9223
)

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'MonkeyCode Skin Injector'
. (Join-Path $PSScriptRoot 'skin-lib.ps1')

$log = Join-Path $PSScriptRoot 'logs\injector.log'
$themeDir = Join-Path $PSScriptRoot ("themes\" + $Theme)

Write-McLog -Path $log -Message "=== injector start theme=$Theme port=$Port pid=$PID ==="

$pack = Get-ThemePack -ThemeDir $themeDir
$bootstrap = New-SkinBootstrapJs -ThemePack $pack
Write-McLog -Path $log -Message ("Theme loaded: {0} v{1} bg={2} cssLen={3} bootstrapLen={4}" -f $pack.Name, $pack.Version, [bool]$pack.BgPath, $pack.Css.Length, $bootstrap.Length)

$injected = @{}
$script:cid = 10
while ($true) {
    try {
        $pages = Get-CdpPageTargets -Port $Port
        foreach ($p in $pages) {
            if ($injected.ContainsKey($p.id)) { continue }
            $script:cid++
            $ok = Push-ThemeToTarget -Target $p -BootstrapJs $bootstrap -LogPath $log
            if ($ok) { $injected[$p.id] = $true }
        }
    } catch {
        # HTTP endpoint failed: app may be closing or starting
    }
    if (-not (Get-Process $script:MC_PROC_NAME -ErrorAction SilentlyContinue)) {
        Write-McLog -Path $log -Message "MonkeyCode exited. Injector stopping."
        break
    }
    Start-Sleep -Seconds 5
}
Write-McLog -Path $log -Message "=== injector exit ==="
