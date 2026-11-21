@echo off
REM Inicia el aplicativo IDEMA - Permisos (Windows).
cd /d "%~dp0backend"
if not exist .env (copy .env.example .env >nul & echo Se creo backend\.env: revise la contrasena de la base de datos.)
if not exist .venv (python -m venv .venv)
.venv\Scripts\pip install -q -r requirements.txt
.venv\Scripts\python server.py
pause
