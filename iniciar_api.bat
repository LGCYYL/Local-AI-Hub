@echo off
title Local AI Hub - LEG3NDY (http://127.0.0.1:8080)
cd /d "%~dp0"

:: Encerra processos orfaos antes de subir
taskkill /F /IM llama-server.exe >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_api_server.ps1"

:: Garante encerramento do backend e liberacao de memoria caso o PowerShell saia
taskkill /F /IM llama-server.exe >nul 2>&1
