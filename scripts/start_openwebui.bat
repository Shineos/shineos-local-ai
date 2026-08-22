@echo off
rem ============================================================================
rem Shineos Local AI - Open WebUI manual start (for debug / service stopped case)
rem Run this file as administrator if the service cannot be started.
rem ============================================================================
setlocal
set "APP_DIR=%~dp0"
set "DATA_DIR=%APP_DIR%data"
set "WEBUI_AUTH=False"
set "ENABLE_SIGNUP=False"
set "OLLAMA_BASE_URL=http://127.0.0.1:11434"
rem デフォルトモデルは「Shineos Chat」（configure_model.ps1 が作成する別名カスタムモデル。
rem ツール無効化済みで「応答なし」を防ぐ。素のモデルタグを指定しないこと）
set "DEFAULT_MODELS=Shineos Chat"
set "RAG_EMBEDDING_ENGINE=ollama"
set "RAG_EMBEDDING_MODEL=nomic-embed-text"
set "CHUNK_SIZE=500"
set "CHUNK_OVERLAP=50"
set "RAG_TOP_K=3"
set "ENABLE_WEB_SEARCH=True"
set "WEB_SEARCH_ENGINE=duckduckgo"
set "BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL=True"
set "BYPASS_WEB_SEARCH_WEB_LOADER=True"
rem モデルが「回答をノートに書く」（write_note）関数呼び出しを選び、
rem チャットに回答が表示されなくなる問題を防ぐため Notes 機能を無効化
set "ENABLE_NOTES=False"

echo Starting Shineos Local AI (Open WebUI)...
echo Open http://localhost:8080 in your browser after the server is up.
"%APP_DIR%venv\Scripts\open-webui.exe" serve --port 8080
endlocal
