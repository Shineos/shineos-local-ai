@echo off
rem ============================================================
rem 社内知恵袋 - ナレッジ再登録ツール
rem
rem knowledge フォルダに PDF・Markdown を追加した後に、
rem このファイルをダブルクリックしてください。
rem 管理者権限の確認画面で「はい」をクリックすると、
rem 自動でナレッジに再登録されます。
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0setup_knowledge.ps1'"
echo.
echo ナレッジ再登録を実行しました。
echo 詳細ログ: C:\Program Files\ShineosQA\logs\setup_knowledge.log
pause
