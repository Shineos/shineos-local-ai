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
    Start-Sleep -Seconds 2

    Log 'upgrading Ollama (silent)'
    Progress 'upgrading Ollama to latest...'
    $p = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        # 診断情報（実行中プロセス・サービスの状態）
        Get-Process -Name ollama -ErrorAction SilentlyContinue | ForEach-Object { Log "ollama process running: $($_.Path)" }
        Get-Service -Name Ollama, ShineosOllama -ErrorAction SilentlyContinue | ForEach-Object { Log "service state: $($_.Name) = $($_.Status)" }
        throw "OllamaSetup exit code $($p.ExitCode)"
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

# --- サービス確認（公式「Ollama」→ 無ければ NSSM フォールバック） ---
$svc = Get-Service -Name 'Ollama' -ErrorAction SilentlyContinue
if ($svc) {
    # 公式サービスがある場合は、以前のフォールバックサービスを削除（起動時競合防止）
    $fbSvc = Get-Service -Name 'ShineosOllama' -ErrorAction SilentlyContinue
    if ($fbSvc) {
        Log 'removing old fallback service (ShineosOllama) to avoid conflict'
        & sc.exe stop ShineosOllama 2>$null | Out-Null
        & sc.exe delete ShineosOllama 2>$null | Out-Null
    }
    Log 'service "Ollama" found: ensure auto start'
    & sc.exe config Ollama start= auto | Out-Null
    if ($svc.Status -ne 'Running') {
        Log 'starting service "Ollama"'
        & sc.exe start Ollama | Out-Null
    }
}
else {
    $fbSvc = Get-Service -Name 'ShineosOllama' -ErrorAction SilentlyContinue
    if (-not $fbSvc) {
        Log 'service "Ollama" not found: register NSSM fallback (ShineosOllama)'
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
    else {
        Log 'service "ShineosOllama" already exists: ensure auto start'
        & sc.exe config ShineosOllama start= auto | Out-Null
    }
    if ($fbSvc.Status -ne 'Running') {
        Log 'starting service "ShineosOllama"'
        & sc.exe start ShineosOllama | Out-Null
    }
}

# --- API 起動待ち（最大60秒） ---
Progress 'starting Ollama service...'
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3
        if ($r.version) { $ready = $true; break }
    }
    catch { Start-Sleep -Seconds 2 }
}
if (-not $ready) { throw 'Ollama API (127.0.0.1:11434) did not become ready' }
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
