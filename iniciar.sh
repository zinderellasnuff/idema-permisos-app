#!/usr/bin/env bash
# Inicia el aplicativo IDEMA - Permisos (Linux/macOS).
set -e
cd "$(dirname "$0")/backend"
[ -f .env ] || { cp .env.example .env; echo "Se creó backend/.env: revise la contraseña de la base de datos."; }
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt
exec .venv/bin/python server.py
