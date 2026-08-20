# setup_ollama.ps1 - Ollama を公式インストーラでサイレント導入
# - 既に導入済みならスキップ（冪等）
# - 公式サービス「Ollama」が無い・停止している場合は NSSM フォールバック登録（ShineosOllama）
# - API (127.0.0.1:11434) の起動を最大60秒待つ
# 終了コード: 0 = 成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [string]$TmpDir
)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $AppDir 'install.log'
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
function Log { param([string]$Message) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

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
$ollamaExe = Get-OllamaExe

if (-not $ollamaExe) {
    $installer = Join-Path $TmpDir 'OllamaSetup.exe'
    if (-not (Test-Path $installer)) {
        $url = 'https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe'
        Log "downloading $url"
        & curl.exe -L --fail --retry 3 --connect-timeout 30 -o $installer $url
        if ($LASTEXITCODE -ne 0) { throw "OllamaSetup download failed (curl exit $LASTEXITCODE)" }
        $size = (Get-Item $installer).Length
        Log "downloaded: $([math]::Round($size / 1MB, 1)) MB"
        if ($size -lt 100MB) { throw "OllamaSetup download looks invalid (${size} bytes) - proxy/block page の可能性" }
    }
    Log 'installing Ollama (silent)'
    $p = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "OllamaSetup exit code $($p.ExitCode)"
    }
    $ollamaExe = Get-OllamaExe
}
if (-not $ollamaExe) { throw 'ollama.exe not found after installation' }
Log "ollama.exe: $ollamaExe"

# --- サービス確認（公式「Ollama」→ 無ければ NSSM フォールバック） ---
$svc = Get-Service -Name 'Ollama' -ErrorAction SilentlyContinue
if ($svc) {
    Log 'service "Ollama" found: ensure auto start'
    & sc.exe config Ollama start= auto | Out-Null
    if ($svc.Status -ne 'Running') {
        Log 'starting service "Ollama"'
        & sc.exe start Ollama | Out-Null
    }
}
else {
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
    Log 'starting service "ShineosOllama"'
    & sc.exe start ShineosOllama | Out-Null
}

# --- API 起動待ち（最大60秒） ---
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
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK: $($_.ScriptStackTrace)"
    exit 1
}
exit 0
