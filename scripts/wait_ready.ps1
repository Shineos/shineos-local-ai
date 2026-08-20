# wait_ready.ps1 - Open WebUI の起動完了を /health で確認する
# 終了コード: 0 = 起動完了 / 1 = タイムアウト
param(
    [int]$Port = 8080,
    [int]$TimeoutSec = 180
)

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
        if ($r.status -eq $true) {
            Write-Output 'ready'
            exit 0
        }
    }
    catch {
        # まだ起動していないだけなので継続
    }
    Start-Sleep -Seconds 2
}

Write-Output 'timeout'
exit 1
