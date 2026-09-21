# 🤖 AGENTS.md — Instructions for AI Assistants & Autonomous Agents

This document provides concise, structured operational guidelines for AI coding agents (such as **Otto Code**, **Cursor**, **Cline**, **Claude Code**, **Antigravity**, **Aider**, **Roo Code**, or **Continue**) interacting with or configuring the **Local AI Hub - LEG3NDY**.

---

## 🎯 Architecture at a Glance
* **Engine:** Precompiled `llama.cpp` Windows binaries with CUDA 13.3 / 12.4 acceleration and Flash Attention.
* **Format:** Universal `.gguf` weights.
* **API Protocol:** Strict OpenAI specification (`/v1/chat/completions`, `/v1/models`).
* **Context Engine:** 128,000 tokens default (`131072`), optimized for 8 GB VRAM via 4-bit KV Cache (`--cache-type-k q4_0 --cache-type-v q4_0`), 4 parallel slots (`-np 4`), and a Unified KV Buffer (`--kv-unified`) supporting simultaneous sub-agent queries without VRAM duplication.
* **Process Lifecycle:** Bound to a Windows OS Kernel **Job Object** (`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`). Terminating the console window or pressing `Ctrl+C` immediately frees all VRAM and RAM without leaving orphan processes.

---

## 🛠️ Commands for Agents

### 1. Initial Setup (First time on any Windows PC)
Run via PowerShell with execution policy bypassed:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\setup.ps1
```
* Installs `uv`, sets up isolated `.venv`, downloads CUDA binaries into `bin/cuda/`, pulls the default code model (`OmniCoder-9B`), and creates desktop shortcut.

### 2. Launch the API Server
Double-click `iniciar_api.bat` or run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_api_server.ps1
```
* Automatically detects any `.gguf` model inside `models\`.
* Kills previous zombie instances on port 8080 before binding.
* Binds to `http://127.0.0.1:8080`.

### 3. Stop the Server
* Close the terminal window (`[X]`) or send `Ctrl+C`.
* The Windows Kernel Job Object terminates `llama-server.exe` instantly.

---

## 🔌 Agent Connection Configurations

### Universal Parameters
* **Base URL:** `http://127.0.0.1:8080/v1`
* **API Key:** `nao-precisa` (or any dummy string)
* **Model Name:** `default` or `OmniCoder-9B` (both resolve to the active model)
* **Context Window:** `131072` (128k)

### A. Otto Code CLI
In your Otto Code model/provider settings:
```json
{
  "provider": "openai-compatible",
  "baseURL": "http://127.0.0.1:8080/v1",
  "apiKey": "nao-precisa",
  "model": "default",
  "contextWindow": 131072,
  "maxTokens": 4096
}
```

### B. Cursor IDE
* Settings ➔ **Models** ➔ **Add Custom Model**: `default`
* **OpenAI Base URL**: `http://127.0.0.1:8080/v1`
* API Key: `nao-precisa`

### C. Cline / Roo Code (VS Code Extension)
* **API Provider:** `OpenAI Compatible`
* **Base URL:** `http://127.0.0.1:8080/v1`
* **API Key:** `nao-precisa`
* **Model ID:** `default`

### D. Continue.dev (`config.json`)
```json
{
  "models": [
    {
      "title": "Local AI Hub (128k)",
      "provider": "openai",
      "model": "default",
      "apiBase": "http://127.0.0.1:8080/v1",
      "apiKey": "nao-precisa",
      "contextLength": 131072
    }
  ]
}
```

### E. Aider CLI
```powershell
aider --openai-api-base http://127.0.0.1:8080/v1 --openai-api-key nao-precisa --model openai/default
```

---

## 🧠 Reasoning & Thinking Control
For models that support internal reasoning/thinking tokens (like DeepSeek-R1 or Qwen-QwQ):
* Disable thinking (instant responses): pass `"extra_body": {"thinking_budget_tokens": 0}`
* Balanced code reasoning: pass `"extra_body": {"thinking_budget_tokens": 512}`
* Unbounded reasoning: pass `"extra_body": {"thinking_budget_tokens": -1}`

---

## 📦 Swapping Models (Plug-and-Play)
Any `.gguf` placed in `models/` is automatically used on next launch.
* **To override model path dynamically:**
  ```powershell
  $env:MODEL_PATH = "C:\caminho\para\qualquer_modelo.gguf"
  .\iniciar_api.bat
  ```
* **Recommended models for 8 GB VRAM + 128k Context:**
  * `OmniCoder-9B-GGUF` (`Q3_K_M` ~4.3 GB)
  * `Qwen2.5-Coder-7B-Instruct-GGUF` (`Q4_K_M` ~4.7 GB)
  * `DeepSeek-R1-Distill-Qwen-7B-GGUF` (`Q4_K_M` ~4.7 GB)
