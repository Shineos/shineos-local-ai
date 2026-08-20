# preflight.ps1 - 環境チェック（OS / ポート8080 / RAM）
# 結果を INI 形式で出力する（Inno Setup 側で GetIniString/GetIniInt により読む）
# 終了コード: 0 = チェックOK / 1 = 問題あり
param(
    [string]$IniPath,
    [int]$Port = 8080
)

$ErrorActionPreference = 'SilentlyContinue'

# --- OSチェック（Windows 10/11 はバージョン 10.0、64bitのみ） ---
$os = Get-CimInstance Win32_OperatingSystem
$osOk = $false
if ($os -and $os.Version -like '10.*' -and [Environment]::Is64BitOperatingSystem) {
    $osOk = $true
}

# --- ポートチェック ---
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
$portFree = -not [bool]$busy

# --- RAM検出（モデル選択ページの表示に使用） ---
$ram = 8
$comp = Get-CimInstance Win32_ComputerSystem
if ($comp -and $comp.TotalPhysicalMemory) {
    $ram = [math]::Round($comp.TotalPhysicalMemory / 1GB)
    if ($ram -lt 4) { $ram = 4 }
}

$lines = @(
    '[preflight]',
    ('os_ok=' + $(if ($osOk) { 'yes' } else { 'no' })),
    ('port_8080_free=' + $(if ($portFree) { 'yes' } else { 'no' })),
    ('ram_gb=' + $ram)
)
$lines -join "`r`n" | Out-File -FilePath $IniPath -Encoding ascii

if ($osOk -and $portFree) { exit 0 } else { exit 1 }
