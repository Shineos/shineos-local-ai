# setup_ollama.ps1 - Ollama を公式インストーラでサイレント導入
# - 既に導入済みならスキップ（冪等）
# - 公式サービス「Ollama」が無い・停止している場合は NSSM フォールバック登録（ShineosOllama）
# - API (127.0.0.1:11434) の起動を最大60秒待つ
# 終了コード: 0 = 成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [string]$TmpDir,
    [string]$ProgressFile = ''
)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $AppDir 'install.log'
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
function Log { param([string]$Message) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8 }
function Progress {
    param([string]$Message)
    if ($ProgressFile) {
        [System.IO.File]::AppendAllText($ProgressFile, "$Message`n", (New-Object System.Text.UTF8Encoding($false)))
    }
}

# インストーラがハングした場合に備えたタイムアウト付き実行
function Invoke-WithTimeout {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int]$TimeoutSec = 600,
        [string]$Label = 'process'
    )
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $p.HasExited) {
        if ((Get-Date) -gt $deadline) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            throw "$Label timed out after ${TimeoutSec}s and was killed: $FilePath"
        }
        Start-Sleep -Seconds 2
    }
    return $p.ExitCode
}

function Get-OllamaExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:ProgramFiles 'Ollama\ollama.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

try {
Log '--- setup_ollama start ---'
Progress 'preparing Ollama'
$ollamaExe = Get-OllamaExe

# --- 古いバージョンは最新に更新する ---
# （旧クライアントは新しいモデル（qwen3.5系）のマニフェストを取得できないため。
#   例: 0.13.5 のような旧版では pull が即失敗する）
$needUpgrade = $false
if ($ollamaExe) {
    $ver = & $ollamaExe --version 2>&1
    Log "ollama version: $ver"
    Progress "ollama version: $ver"
    if ($ver -match 'version is (\d+)\.(\d+)') {
        if ([int]$Matches[1] -eq 0 -and [int]$Matches[2] -lt 30) { $needUpgrade = $true }
    }
    else { $needUpgrade = $true }
}
else { $needUpgrade = $true }

if ($needUpgrade) {
    $installer = Join-Path $TmpDir 'OllamaSetup.exe'
    if (-not (Test-Path $installer)) {
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            throw 'curl.exe not found (Windows 10 1803 以降が必要)'
        }
        $url = 'https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe'
        Log "downloading $url"
        Progress 'downloading Ollama (1.5GB)...'
        & curl.exe -L --fail --retry 3 --connect-timeout 30 -o $installer $url
        if ($LASTEXITCODE -ne 0) { throw "OllamaSetup download failed (curl exit $LASTEXITCODE)" }
        $size = (Get-Item $installer).Length
        Log "downloaded: $([math]::Round($size / 1MB, 1)) MB"
        Progress "download complete: $([math]::Round($size / 1MB, 1)) MB"
        if ($size -lt 100MB) { throw "OllamaSetup download looks invalid (${size} bytes) - proxy/block page の可能性" }
    }
    # 旧バージョンのOllamaプロセス/サービスが動作していると、実行中ファイルを
    # 置換できずインストールが失敗する（ERROR_ACCESS_DENIED = exit code 5）ため先に停止する
    Log 'stopping old Ollama services/processes before upgrade'
    Progress 'stopping old Ollama services...'
    & sc.exe stop ShineosOllama 2>$null | Out-Null
    & sc.exe stop Ollama 2>$null | Out-Null
    Get-Process -Name ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # プロセスの終了を確認（最大15秒）
    for ($i = 0; $i -lt 15; $i++) {
        if (-not (Get-Process -Name ollama -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 1
    }

    # 上書き更新は旧版アンインストーラがハングすることがあるため、
    # 先に旧版をアンインストールしてからクリーン導入する（各ステップはタイムアウト付き）
    $oldUnins = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\unins000.exe'
    if (Test-Path $oldUnins) {
        Log "uninstalling old Ollama: $oldUnins"
        Progress 'uninstalling old Ollama...'
        $uninsCode = Invoke-WithTimeout -FilePath $oldUnins -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -TimeoutSec 300 -Label 'old Ollama uninstaller'
        Log "old Ollama uninstaller exit code: $uninsCode"
    }

    Log 'installing Ollama (silent)'
    Progress 'installing Ollama (latest version)...'
    $installCode = Invoke-WithTimeout -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -TimeoutSec 900 -Label 'OllamaSetup'
    Log "OllamaSetup exit code: $installCode"
    if ($installCode -ne 0 -and $installCode -ne 3010) {
        # 診断情報（実行中プロセス・サービスの状態）
        Get-Process -Name ollama -ErrorAction SilentlyContinue | ForEach-Object { Log "ollama process running: $($_.Path)" }
        Get-Service -Name Ollama, ShineosOllama -ErrorAction SilentlyContinue | ForEach-Object { Log "service state: $($_.Name) = $($_.Status)" }
        throw "OllamaSetup exit code $installCode"
    }
    $ollamaExe = Get-OllamaExe
    if (-not $ollamaExe) { throw 'ollama.exe not found after installation' }
    $ver = & $ollamaExe --version 2>&1
    Log "ollama version after upgrade: $ver"
    Progress "ollama upgraded: $ver"
}
else {
    Log 'ollama version is current (no upgrade needed)'
    Progress 'ollama is up to date'
}
Log "ollama.exe: $ollamaExe"

# --- Ollama の起動（公式サービス → NSSM フォールバック → 直接起動 の3段構え） ---
function Test-OllamaApi {
    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3
        return [bool]$r.version
    }
    catch { return $false }
}
function Wait-OllamaApi {
    param([int]$Seconds = 20)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-OllamaApi) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# 1) 既に起動していれば何もしない
if (Test-OllamaApi) {
    Log 'Ollama API already running'
    Progress 'Ollama ready'
    Progress 'PROGRESS_DONE:0'
    exit 0
}

$svc = Get-Service -Name 'Ollama' -ErrorAction SilentlyContinue
$fbSvc = Get-Service -Name 'ShineosOllama' -ErrorAction SilentlyContinue

# 2) 公式サービスを優先して起動
if ($svc) {
    Log 'service "Ollama" found: ensure auto start and start'
    Progress 'starting Ollama service...'
    & sc.exe config Ollama start= auto | Out-Null
    if ($svc.Status -ne 'Running') { & sc.exe start Ollama | Out-Null }
    if (Wait-OllamaApi -Seconds 20) {
        # 公式が動いたのでフォールバックを削除（起動時競合防止）
        if ($fbSvc) {
            Log 'removing fallback service (ShineosOllama)'
            & sc.exe stop ShineosOllama 2>$null | Out-Null
            & sc.exe delete ShineosOllama 2>$null | Out-Null
        }
        Log 'Ollama ready (official service)'
        Progress 'Ollama ready'
        Progress 'PROGRESS_DONE:0'
        exit 0
    }
    Log 'official service did not become ready - trying fallback'
}

# 3) NSSM フォールバックサービス（既存 or 新規登録）を起動
if (-not $fbSvc) {
    Log 'registering NSSM fallback (ShineosOllama)'
    Progress 'registering Ollama service...'
    $nssm = Join-Path $TmpDir 'nssm.exe'
    if (-not (Test-Path $nssm)) { throw "nssm.exe not found: $nssm" }
    $logDir = Join-Path $AppDir 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    & $nssm install ShineosOllama $ollamaExe 'serve' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'nssm install ShineosOllama failed' }
    & $nssm set ShineosOllama Start SERVICE_AUTO_START | Out-Null
    & $nssm set ShineosOllama AppStdout (Join-Path $logDir 'ollama.log') | Out-Null
    & $nssm set ShineosOllama AppStderr (Join-Path $logDir 'ollama.err.log') | Out-Null
}
Log 'starting fallback service (ShineosOllama)'
Progress 'starting Ollama service...'
& sc.exe config ShineosOllama start= auto | Out-Null
if ((Get-Service -Name 'ShineosOllama' -ErrorAction SilentlyContinue).Status -ne 'Running') {
    & sc.exe start ShineosOllama | Out-Null
}
if (Wait-OllamaApi -Seconds 20) {
    Log 'Ollama ready (fallback service)'
    Progress 'Ollama ready'
    Progress 'PROGRESS_DONE:0'
    exit 0
}

# 4) 最終フォールバック: サービスが機能しない場合はプロセスを直接起動
Log 'services failed - starting ollama.exe serve directly'
Progress 'starting Ollama directly...'
Start-Process -FilePath $ollamaExe -ArgumentList 'serve' -WindowStyle Hidden
if (Wait-OllamaApi -Seconds 15) {
    Log 'Ollama ready (direct process)'
    Progress 'Ollama ready'
    Progress 'PROGRESS_DONE:0'
    exit 0
}

# 5) 診断情報を記録して失敗
Get-Service -Name Ollama, ShineosOllama -ErrorAction SilentlyContinue | ForEach-Object { Log "service state: $($_.Name) = $($_.Status)" }
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('Ollama', 'ShineosOllama') } | ForEach-Object { Log "service info: $($_.Name) state=$($_.State) path=$($_.PathName)" }
throw 'Ollama API (127.0.0.1:11434) did not become ready'
Log '--- setup_ollama done ---'
Progress 'Ollama ready'
Progress 'PROGRESS_DONE:0'
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK: $($_.ScriptStackTrace)"
    Progress 'PROGRESS_DONE:1'
    exit 1
}
exit 0
