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
set "RAG_EMBEDDING_ENGINE=ollama"
set "RAG_EMBEDDING_MODEL=nomic-embed-text"
set "ENABLE_WEB_SEARCH=True"
set "WEB_SEARCH_ENGINE=duckduckgo"

echo Starting Shineos Local AI (Open WebUI)...
echo Open http://localhost:8080 in your browser after the server is up.
"%APP_DIR%venv\Scripts\open-webui.exe" serve --port 8080
endlocal
