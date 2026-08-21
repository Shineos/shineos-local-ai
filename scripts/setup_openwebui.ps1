# setup_openwebui.ps1 - AIモデルのダウンロード / open-webui 実行環境の構築
# モード:
#   -Mode models : Ollama に LLM モデルと埋め込みモデルをダウンロード（長い処理）
#   -Mode app    : venv 作成 → torch(CPU) → open-webui をインストール（長い処理）
# 各処理は冪等（再実行時はスキップ）
# 終了コード: 0 = 成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [string]$Mode,
    [string]$Model = 'qwen3.5:4b',
    [string]$EmbeddingModel = 'nomic-embed-text',
    [string]$OpenWebuiVersion = '0.11.0',
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
if ($Mode -eq 'models') {
    # ---------- モデルダウンロード ----------
    Log "--- models: $Model / $EmbeddingModel ---"
    $ollama = Get-OllamaExe
    if (-not $ollama) { throw 'ollama.exe not found' }
    $ver = & $ollama --version 2>&1
    Log "ollama version: $ver"

    Log "pulling $Model"
    Progress "downloading model $Model (3.4GB)..."
    # 外部コマンドの stderr 出力（進捗）で NativeCommandError が発生しないよう
    # キャプチャ中のみ ErrorActionPreference を緩める
    $ErrorActionPreference = 'Continue'
    $pullOut = & $ollama pull $Model 2>&1 | ForEach-Object { Progress $_; $_ }
    $pullCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop
    if ($pullCode -ne 0) {
        $pullOut | ForEach-Object { Log "ollama-pull: $_" }
        $errLog = Join-Path $AppDir 'logs\ollama.err.log'
        if (Test-Path $errLog) {
            Log '--- ollama.err.log (last 30 lines) ---'
            Get-Content $errLog -Tail 30 | ForEach-Object { Log "ollama-err: $_" }
        }
        throw "model pull failed: $Model (exit $pullCode)"
    }
    Log "pulled $Model"
    Progress "model $Model downloaded"

    Log "pulling $EmbeddingModel"
    Progress "downloading embedding model $EmbeddingModel (274MB)..."
    $ErrorActionPreference = 'Continue'
    $pullOut2 = & $ollama pull $EmbeddingModel 2>&1 | ForEach-Object { Progress $_; $_ }
    $pullCode2 = $LASTEXITCODE
    $ErrorActionPreference = 'Stop
    if ($pullCode2 -ne 0) {
        $pullOut2 | ForEach-Object { Log "ollama-pull: $_" }
        throw "embedding model pull failed: $EmbeddingModel (exit $pullCode2)"
    }
    Log "pulled $EmbeddingModel"
    Progress "embedding model downloaded"
    Log 'models ready'
}
elseif ($Mode -eq 'app') {
    # ---------- venv + torch(CPU) + open-webui ----------
    Log '--- app install ---'
    $pyExe = Join-Path $AppDir 'python\python.exe'
    # setup_python.ps1 が既存Pythonを再利用した場合は python-path.txt に実パスが記録される
    $pathFile = Join-Path $AppDir 'python-path.txt'
    if (Test-Path $pathFile) {
        $candidate = (Get-Content $pathFile -Raw).Trim()
        if ($candidate -and (Test-Path $candidate)) { $pyExe = $candidate }
    }
    if (-not (Test-Path $pyExe)) { throw "python.exe not found: $pyExe" }

    $venvDir = Join-Path $AppDir 'venv'
    $venvPython = Join-Path $venvDir 'Scripts\python.exe'
    if (-not (Test-Path $venvPython)) {
        Log 'creating venv'
        Progress 'creating python venv...'
        & $pyExe -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
    }

    Log 'upgrading pip'
    Progress 'upgrading pip...'
    & $venvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'pip upgrade failed' }

    # torch は CPU 版を先に導入（Windows 既定の CUDA 版 2.5GB 超を回避）
    Log 'installing torch (CPU)'
    Progress 'installing torch (CPU)...'
    & $venvPython -m pip install torch --index-url https://download.pytorch.org/whl/cpu
    if ($LASTEXITCODE -ne 0) { throw 'torch install failed' }

    Log "installing open-webui==$OpenWebuiVersion"
    Progress 'installing open-webui...'
    & $venvPython -m pip install "open-webui==$OpenWebuiVersion"
    if ($LASTEXITCODE -ne 0) { throw 'open-webui install failed' }

    Log 'app install done'
    Progress 'open-webui installed'
}
else {
    throw "unknown mode: $Mode"
}
Progress 'PROGRESS_DONE:0'
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK: $($_.ScriptStackTrace)"
    Progress 'PROGRESS_DONE:1'
    exit 1
}
exit 0
