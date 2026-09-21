# ⚡ Local AI Hub - LEG3NDY

Um hub local de alta performance para execução de modelos de linguagem (LLMs) como uma **API compatível com OpenAI** (`/v1/chat/completions`). Projetado especificamente pela **LEG3NDY** para alimentar **agentes autônomos de código** (como **Otto Code**, **Cursor**, **Cline**, **Aider**) e aplicações de IA em PCs com GPUs comerciais (8 GB a 16 GB de VRAM como RTX 5060, 4060, 3060).

---

## 🎯 Visão Geral e Arquitetura

O **Local AI Hub** é agnóstico a modelos: ele funciona como um motor de inferência *plug-and-play*. Você pode plugar qualquer modelo no formato `.gguf` (OmniCoder, Qwen, DeepSeek-R1, Llama 3, Bonsai, etc.) e ele disponibilizará automaticamente uma API OpenAI padronizada na porta local.

### Destaques:
* **Zero Bloat de RAM:** Não utiliza interfaces gráficas pesadas que vazam memória. O modelo roda 100% isolado na GPU.
* **Contexto Gigante (até 128.000 tokens):** Graças à compressão do KV Cache em 4-bit (`q4_0`) e ao Flash Attention (`-fa on`), contextos de 128k cabem confortavelmente em placas de 8 GB de VRAM.
* **Auto-Recuperação de Zumbis:** O launcher encerra automaticamente processos órfãos anteriores antes de subir uma nova instância, eliminando conflitos de porta (HTTP 400/404).
* **Compatibilidade Total OpenAI:** Suporte nativo a streaming, chamadas de ferramentas (*tool calling* via Jinja templates) e orçamento dinâmico de raciocínio (*thinking budget*).

---

## 🚀 Como Instalar em Qualquer PC (Windows)

### Pré-requisitos:
1. Windows 10 ou 11 (64-bit).
2. [Python 3.10+](https://www.python.org/downloads/) instalado e adicionado ao PATH.
3. Placa de vídeo NVIDIA (RTX série 30, 40 ou 50) com drivers atualizados.

### Passo 1: Clonar o repositório
```powershell
git clone https://github.com/LGCYYL/Local-AI-Hub.git
cd Local-AI-Hub
```

### Passo 2: Executar o Instalador Automático
Abra o PowerShell dentro da pasta e execute:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\setup.ps1
```

**O que o instalador faz sozinho:**
1. Valida o Python e instala o gerenciador `uv`.
2. Cria o ambiente virtual isolado `.venv` com ferramentas Hugging Face.
3. Detecta a GPU NVIDIA (compatível com os drivers mais recentes via `CUDA UMD Version`) e baixa os binários otimizados do `llama.cpp` CUDA 13.3 / 12.4 para `bin/cuda/`.
4. Baixa o modelo padrão recomendado para código (`OmniCoder-9B` ou o configurado) na pasta `models/`.
5. Cria o atalho executável **`Local AI Hub - LEG3NDY`** diretamente na sua Área de Trabalho.

---

## 🕹️ Como Iniciar o Servidor

Você pode iniciar o servidor de duas formas:
1. **Pela Área de Trabalho:** Dê dois cliques no atalho **`Local AI Hub - LEG3NDY`**.
2. **Pelo Terminal:** Execute:
   ```cmd
   .\iniciar_api.bat
   ```

* **Para encerrar o servidor e liberar recursos:** Basta fechar a janela do terminal no botão **`[X]`** ou apertar **`Ctrl + C`**. O sistema agora está atrelado ao kernel do Windows (via *Job Object* `KILL_ON_JOB_CLOSE`), então o processo do servidor e toda a memória de GPU/RAM são encerrados na mesma fração de segundo em que a janela fecha.

---

## ⚙️ Otimizações de Engenharia (Por que não trava o PC?)

| Flag / Otimização | Função | Benefício Real |
| :--- | :--- | :--- |
| **`-np 1` (Single Slot)** | Aloca buffer para apenas 1 requisição concorrente. | Impede o backend de multiplicar o uso de memória por 4 slots ociosos. |
| **`--cache-type-k q4_0` / `v q4_0`** | Comprime o KV Cache de contexto em 4-bit. | Reduz o custo de VRAM por token em **3.5x**, permitindo 128k de contexto em placas de 8 GB. |
| **`-fa on` (Flash Attention)** | Ativa atenção vetorizada dinâmica. | O contexto só consome a memória que o prompt realmente utiliza no momento. |
| **`--no-webui`** | Desativa servidores web internos e proxies CORS. | Zero consumo desnecessário de CPU e memória RAM do sistema. |
| **Auto-Kill de Zumbis** | Encerra instâncias antigas antes de inicializar. | Garante que o cliente sempre conecte na instância ativa e correta. |

---

## 🔌 Como Conectar no Otto Code ou Outros Clientes

O servidor expõe uma API compatível com o padrão OpenAI em:
* **Base URL:** `http://127.0.0.1:8080/v1`
* **Model ID:** Nome do modelo ativo (ex: `OmniCoder-9B`, `default`)
* **API Key:** `nao-precisa` *(qualquer texto ou string serve)*
* **Guia para Agentes:** Veja o arquivo [`AGENTS.md`](AGENTS.md) para documentação técnica voltada para assistentes autônomos.

### Configuração no Otto Code / Cursor / Cline:
| Ferramenta | Provedor | Base URL | Modelo | API Key | Contexto |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Otto Code** | `openai-compatible` | `http://127.0.0.1:8080/v1` | `default` | `nao-precisa` | `131072` (128k) |
| **Cursor** | Custom OpenAI | `http://127.0.0.1:8080/v1` | `default` | `nao-precisa` | Auto |
| **Cline / Roo** | OpenAI Compatible | `http://127.0.0.1:8080/v1` | `default` | `nao-precisa` | `131072` |
| **Aider** | OpenAI | `http://127.0.0.1:8080/v1` | `openai/default`| `nao-precisa` | Auto |

### Exemplo de Chamada em Python:
```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="nao-precisa"
)

response = client.chat.completions.create(
    model="default",
    messages=[
        {"role": "user", "content": "Explique a arquitetura do projeto."}
    ],
    max_tokens=500,
    extra_body={
        "thinking_budget_tokens": 100  # Orçamento dinâmico de pensamento/raciocínio
    }
)

print(response.choices[0].message.content)
```

### Controle de Pensamento (Thinking / Reasoning):
Para modelos de raciocínio (que utilizam tags `<think>`), controle o tempo de reflexão enviando:
* `"thinking_budget_tokens": 0` ➔ Desliga o raciocínio (resposta imediata para saudações e comandos simples).
* `"thinking_budget_tokens": 100` a `2048` ➔ Raciocínio equilibrado para geração de código e tarefas complexas.
* `"thinking_budget_tokens": -1` ➔ Raciocínio irrestrito.

---

## 📦 Como Adicionar Outros Modelos (Plug-and-Play)

O hub detecta automaticamente qualquer arquivo `.gguf` dentro da pasta `models/`:
1. Baixe o modelo desejado no Hugging Face (em formato `.gguf`).
2. Coloque-o dentro de `models/<nome_do_modelo>/`.
3. Abra o servidor pelo atalho. O script detectará o novo modelo e subirá a API automaticamente!

---

## 🛠️ Solução de Problemas (Troubleshooting)

1. **Erro: "request exceeds available context size":**
   * O servidor já sobe com 128k (`131072 tokens`). Caso queira ajustar manualmente, defina a variável `$env:CTX = "65536"` antes de iniciar.
2. **Lentidão na primeira mensagem:**
   * É normal levar alguns segundos a mais na primeira mensagem se o seu cliente enviar um prompt de sistema de 20k+ tokens frios. Da segunda mensagem em diante, o **Prompt Caching** entra em ação e responde quase que instantaneamente (< 400ms).
3. **Porta em conflito:**
   * O inicializador mata automaticamente processos presos do `llama-server`. Se precisar mudar a porta, defina `$env:PORT = "8081"`.
