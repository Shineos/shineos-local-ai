# run_all.ps1 - 長いセットアップ手順を1つのコンソールで順に実行するラッパー
# - 各ステップの開始・成功・失敗をコンソールと install.log の両方に記録する
# - いずれかのステップが失敗したら、そこで停止して終了コードを返す
# 終了コード: 0 = 全ステップ成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [string]$TmpDir,
    [string]$PythonVersion = '3.12.10',
    [string]$Model = 'qwen3.5:4b',
    [string]$OpenWebuiVersion = '0.11.0'
)

$ErrorActionPreference = 'Continue'
$LogFile = Join-Path $AppDir 'install.log'
$here = $PSScriptRoot
# 前回の失敗情報をクリア
'' | Out-File -FilePath (Join-Path $TmpDir 'step_error.txt') -Encoding ascii -ErrorAction SilentlyContinue

function Log-Console {
    param([string]$Message)
    Write-Output $Message
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Script,
        [string[]]$Params
    )
    Log-Console "===== STEP START: $Name ====="
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here $Script) @Params
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Log-Console "===== STEP FAILED: $Name (exit $code) ====="
        # インストーラのエラーダイアログに表示するため、失敗情報をファイルに残す
        "STEP FAILED: $Name (exit $code)" | Out-File -FilePath (Join-Path $TmpDir 'step_error.txt') -Encoding ascii
        exit $code
    }
    Log-Console "===== STEP OK: $Name ====="
}

Invoke-Step -Name 'Python (3.12)' -Script 'setup_python.ps1' -Params @('-AppDir', $AppDir, '-TmpDir', $TmpDir, '-Version', $PythonVersion)
Invoke-Step -Name 'Ollama' -Script 'setup_ollama.ps1' -Params @('-AppDir', $AppDir, '-TmpDir', $TmpDir)
Invoke-Step -Name 'AI Models' -Script 'setup_openwebui.ps1' -Params @('-AppDir', $AppDir, '-Mode', 'models', '-Model', $Model)
Invoke-Step -Name 'Open WebUI' -Script 'setup_openwebui.ps1' -Params @('-AppDir', $AppDir, '-Mode', 'app', '-OpenWebuiVersion', $OpenWebuiVersion)

Log-Console '===== ALL STEPS COMPLETED ====='
exit 0
