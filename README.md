# agentec-openclaw-stack

Orquestador del entorno AgenTEC sobre OpenClaw. Este es el **único repositorio que el usuario clona manualmente** la primera vez. El resto se descarga y actualiza automáticamente.

<a id="arquitectura"></a>
## Arquitectura

```
~/agentec/
├── agentec-openclaw-stack/   ← este repo (orquestador)
├── openclaw/                 ← descargado automáticamente desde GitHub
├── agentec-catalog/          ← catálogo de releases y profiles aprobados
├── agentec-skills/           ← instrucciones de skills para OpenClaw
├── agentec-tools/            ← tools ejecutables (Playwright, runners)
├── artifacts/                ← capturas y resultados generados
└── logs/                     ← logs de bootstrap, update y healthcheck
```

OpenClaw es una **dependencia externa**, no está dentro de este repo. Se descarga desde `https://github.com/openclaw/openclaw`.

---

## Índice rápido (clic para navegar)

- [Arquitectura](#arquitectura)
- [Instalación por sistema operativo](#instalacion)
- [Configuración post-instalación](#config-post)
- [Uso diario](#uso-diario)
- [Comandos avanzados](#comandos-avanzados)
- [Shadow mode](#shadow-mode)
- [Paso 12: staging sobre MCP Python](#paso-12)
- [Paso 13: regresión + carga básica](#paso-13)
- [Variables de entorno](#variables-entorno)
- [Configuración reusable por terceros](#config-reusable)
- [Actualización mensual automatizada](#actualizacion)
- [Estructura de archivos](#estructura)
- [Criterio de ambiente listo](#criterio-listo)
- [FAQ de instalación y troubleshooting](#faq)
- [Persistencia](#persistencia)
- [Repositorios relacionados](#repos)

---

<a id="instalacion"></a>
## Instalación por sistema operativo

### Linux (Ubuntu 20.04+ / Debian / cualquier distro con apt)

**Prerrequisitos:**

```bash
# Git
sudo apt update && sudo apt install -y git curl

# Docker Engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker          # o cierra y abre sesión para que tome efecto

# Verificar
docker --version
docker compose version
```

**Instalar AgenTEC:**

```bash
git clone https://github.com/tluisguereroItesm/agentec-openclaw-stack.git ~/agentec/agentec-openclaw-stack
cd ~/agentec/agentec-openclaw-stack
chmod +x scripts/*.sh
./scripts/bootstrap.sh
```

---

### macOS (12 Monterey o superior)

**Prerrequisitos:**

1. Instala [Docker Desktop para Mac](https://www.docker.com/products/docker-desktop/) y ábrelo al menos una vez.
2. Git ya viene con Xcode Command Line Tools:
   ```bash
   xcode-select --install
   ```

**Instalar AgenTEC:**

```bash
git clone https://github.com/tluisguereroItesm/agentec-openclaw-stack.git ~/agentec/agentec-openclaw-stack
cd ~/agentec/agentec-openclaw-stack
chmod +x scripts/*.sh
./scripts/bootstrap.sh
```

> **Nota:** El script detecta macOS automáticamente y ajusta los comandos internos (ej. `sed`).

---

### Windows (WSL2 + Docker Desktop)

WSL2 convierte tu Windows en un entorno Linux real. Es el método recomendado.

**Paso 1 — Instalar WSL2** (en PowerShell como Administrador):

```powershell
wsl --install
```

Reinicia la máquina cuando se solicite. Esto instala Ubuntu por defecto.

**Paso 2 — Instalar Docker Desktop:**

1. Descarga [Docker Desktop para Windows](https://www.docker.com/products/docker-desktop/).
2. Durante la instalación, activa la opción **"Use WSL 2 based engine"**.
3. En Docker Desktop → Settings → Resources → WSL Integration → activa tu distro (Ubuntu).

**Paso 3 — Abrir una terminal Ubuntu (WSL2)** y ejecutar:

```bash
# Actualizar paquetes e instalar git y curl
sudo apt update && sudo apt install -y git curl

# Instalar AgenTEC
git clone https://github.com/tluisguereroItesm/agentec-openclaw-stack.git ~/agentec/agentec-openclaw-stack
cd ~/agentec/agentec-openclaw-stack
chmod +x scripts/*.sh
./scripts/bootstrap.sh
```

> **Importante:** Ejecuta siempre los comandos dentro de la terminal Ubuntu/WSL2, no en PowerShell ni CMD.

---

<a id="config-post"></a>
## Configuración post-instalación

El `bootstrap.sh` es interactivo: pregunta proveedor de modelo (OpenRouter, OpenAI, Anthropic, Gemini), nombre del modelo y API key. Al terminar crea tu `.env` automáticamente.

**Si usas Microsoft 365 (Graph API)**, edita el archivo de perfil de Graph:

```bash
nano config/tools/graph/profiles.json
```

Reemplaza los campos `tenantId` y `clientId` con los valores de tu Azure App Registration:

```json
{
  "defaultProfile": "default",
  "profiles": {
    "default": {
      "tenantId": "TU-TENANT-ID-AQUI",
      "clientId": "TU-CLIENT-ID-AQUI",
      ...
    }
  }
}
```

> El archivo `config/tools/graph/profiles.example.json` tiene la estructura completa con todos los scopes necesarios por tool.

---

<a id="uso-diario"></a>
## Uso diario (después del primer bootstrap)

```bash
cd ~/agentec/agentec-openclaw-stack

./scripts/start.sh        # arrancar el stack
./scripts/stop.sh         # detener el stack
./scripts/update.sh       # actualizar todos los repos (mensual)
./scripts/healthcheck.sh  # validar que todo responde
```

<a id="comandos-avanzados"></a>
## Comandos avanzados

| Acción | Comando |
|--------|---------|
| Arranque normal | `./scripts/start.sh` |
| Parar | `./scripts/stop.sh` |
| Actualización mensual | `./scripts/update.sh` |
| Validar ambiente | `./scripts/healthcheck.sh` |
| Comparar MCP Node vs Python (shadow) | `./scripts/mcp-shadow-compare.sh` |
| Golden test Node vs Python | `./scripts/mcp-golden-test.sh` |
| Switch staging a MCP Python | `./scripts/staging-switch-to-python-mcp.sh` |
| Smoke E2E staging (MCP Python) | `./scripts/staging-smoke-e2e.sh` |
| Regresión staging (métricas) | `./scripts/staging-regression.sh` |
| Carga básica staging (métricas) | `./scripts/staging-load-test.sh` |

<a id="shadow-mode"></a>
## Shadow mode (Node + Python en paralelo)

Para ejecutar pruebas espejo durante migración:

1. Activa en `.env`:
	- `AGENTEC_SHADOW_MODE=1`
	- `AGENTEC_MCP_PY_PORT=3102` (o el puerto que prefieras)
2. Levanta stack:
	- `./scripts/start.sh` (o `./scripts/bootstrap.sh` en primera instalación)
3. Corre comparación espejo:
	- `./scripts/mcp-shadow-compare.sh`
4. Corre golden test (contrato + artefactos + latencia):
	- `./scripts/mcp-golden-test.sh`

En este modo corren simultáneamente:
- `agentec-mcp-server` (Node) en `AGENTEC_MCP_PORT`
- `agentec-mcp-server-py` (Python) en `AGENTEC_MCP_PY_PORT`

<a id="paso-12"></a>
## Paso 12: staging sobre MCP Python

Para validar staging con MCP Python como endpoint principal:

1. Cargar entorno staging en `.env` (por ejemplo copiando `.env.staging`).
2. Ejecutar switch de OpenClaw config:
	- `./scripts/staging-switch-to-python-mcp.sh`
3. Ejecutar smoke E2E:
	- `./scripts/staging-smoke-e2e.sh`

El smoke verifica:
- Gateway `/healthz`
- MCP Python `/health`
- `tools/list` contiene el set reusable (`web_login_playwright`, `web_login_playwright_py`, `graph_mail`, `graph_files`)
- `tools/call` de tool crítica responde `success`

<a id="paso-13"></a>
## Paso 13: regresión + carga básica con métricas

Con staging apuntando a MCP Python:

1. Regresión funcional repetitiva:
	- `./scripts/staging-regression.sh`
2. Carga básica concurrente:
	- `./scripts/staging-load-test.sh`

Ambos scripts generan reportes JSON en `artifacts/` con:
- latencias (`avg`, `p95`, `max`)
- `error_rate`
- (carga) `throughput_rps`

<a id="variables-entorno"></a>
## Variables de entorno

Copia `.env.example` a `.env` y define al menos:

| Variable | Descripción |
|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Token de autenticación del gateway (obligatorio) |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | API key del proveedor de modelo (al menos uno) |
| `OPENCLAW_TZ` | Zona horaria (default: `America/Mexico_City`) |

Ver `.env.example` para todas las opciones disponibles.

Variables shadow destacadas:

| Variable | Descripción |
|----------|-------------|
| `AGENTEC_SHADOW_MODE` | `1` activa servicio MCP Python paralelo |
| `AGENTEC_MCP_PY_PORT` | Puerto expuesto del MCP Python shadow |
| `AGENTEC_MCP_TIMEOUT_SECONDS` | Timeout default de `tools/call` en Python |
| `AGENTEC_MCP_MAX_TIMEOUT_SECONDS` | Timeout máximo permitido por request |
| `AGENTEC_MCP_LOG_LEVEL` | Nivel de logs del MCP Python |
| `AGENTEC_GOLDEN_TEST` | `1` ejecuta golden test dentro de `healthcheck.sh` |
| `AGENTEC_GOLDEN_MAX_LATENCY_DELTA_MS` | Delta máximo aceptable Node vs Python |
| `AGENTEC_GOLDEN_MAX_PY_TO_NODE_RATIO` | Ratio máximo de latencia Python/Node |
| `AGENTEC_REGRESSION_ITERATIONS_LIST` | Iteraciones de `tools/list` en regresión |
| `AGENTEC_REGRESSION_ITERATIONS_CALL` | Iteraciones de `tools/call` en regresión |
| `AGENTEC_REGRESSION_MAX_ERROR_RATE` | Error rate máximo permitido en regresión |
| `AGENTEC_LOAD_TOTAL_REQUESTS` | Total de requests en prueba de carga |
| `AGENTEC_LOAD_CONCURRENCY` | Concurrencia para load test |
| `AGENTEC_LOAD_MAX_ERROR_RATE` | Error rate máximo permitido en carga |
| `AGENTEC_LOAD_P95_TARGET_MS` | Objetivo de p95 en carga |

<a id="config-reusable"></a>
## Configuración reusable por terceros

Además de `.env`, el stack usa perfiles versionables en `config/` para que cualquier persona
pueda reutilizar el entorno sin editar código.

### Estructura esperada

```text
agentec-openclaw-stack/
├── .env                  ← secretos y valores sensibles locales
└── config/
		└── tools/
				├── web-login/
				│   ├── profiles.example.json
				│   └── profiles.json
				└── graph/
						├── profiles.example.json
						└── profiles.json
```

### Qué vive en cada lugar

- `.env`
	- tokens del gateway/MCP
	- API keys de modelos
	- defaults sensibles de Graph (`tenant`, `clientId`, token store)
- `config/tools/web-login/profiles.json`
	- URLs, selectors y timeouts por portal web
- `config/tools/graph/profiles.json`
	- perfiles de tenant, scopes y defaults de OneDrive/SharePoint

### Flujo recomendado para un usuario nuevo

1. Clonar `agentec-openclaw-stack`.
2. Ejecutar `./scripts/bootstrap.sh`.
3. Editar `.env`.
4. Ajustar `config/tools/web-login/profiles.json` y `config/tools/graph/profiles.json`.
5. Levantar con `./scripts/start.sh`.

Con esto, el entorno queda listo para que las tools lean configuración sin tocar código.

<a id="actualizacion"></a>
## Actualización mensual automatizada

### Opción A — cron
```bash
crontab -e
# Añadir:
0 3 1 * * /home/TU_USUARIO/agentec/agentec-openclaw-stack/scripts/update.sh >> /home/TU_USUARIO/agentec/logs/cron-update.log 2>&1
```

### Opción B — systemd timer (requiere systemd en WSL)
Ver `install/cron.monthly.example` para las instrucciones completas.

<a id="estructura"></a>
## Estructura de archivos

```
agentec-openclaw-stack/
├── docker-compose.yml          # Servicios: openclaw-gateway + agentec-mcp-server
├── .env.example                # Plantilla de variables de entorno
├── config/
│   ├── openclaw.json           # Configuración base de OpenClaw (copiada a ~/.openclaw/)
│   └── tools/                  # Perfiles reutilizables de portales y Graph
├── scripts/
│   ├── bootstrap.sh            # Instalación inicial completa
│   ├── update.sh               # Actualización mensual de repos y servicios
│   ├── start.sh                # Arranque normal
│   ├── stop.sh                 # Parada
│   └── healthcheck.sh          # Validación del ambiente
├── install/
│   └── cron.monthly.example    # Ejemplo de automatización mensual
└── README.md
```

<a id="criterio-listo"></a>
## Criterio de "ambiente listo"

`healthcheck.sh` valida:

- [x] Docker responde sin sudo
- [x] Contenedores `openclaw-gateway` y `agentec-mcp-server` corriendo
- [x] Gateway responde en `/healthz`
- [x] MCP responde en `/health`
- [x] Repos sincronizados con remote
- [x] Skills reusable (`web-login-monitor`, `web-login-monitor-py`, `graph-mail`, `graph-files`) disponibles en `agentec-skills/skills/`
- [x] `openclaw.json` presente en `~/.openclaw/`
- [x] perfiles locales de `web-login` y `graph` presentes en `config/tools/`
- [x] Tools reusable expuestas vía MCP (`web_login_playwright`, `web_login_playwright_py`, `graph_mail`, `graph_files`)

<a id="faq"></a>
## FAQ de instalación y troubleshooting (Q&A)

Si algo no quedó bien instalado, usa esta guía rápida de preguntas y respuestas.

### Runbook rápido (10 comandos)

Ejecuta estos comandos en orden para diagnosticar el 90% de incidencias post-instalación:

```bash
cd ~/agentec/agentec-openclaw-stack
docker compose config
docker compose ps
docker compose logs --tail=120 openclaw-gateway
docker compose logs --tail=120 agentec-mcp-server
curl -fsS http://localhost:18789/healthz || true
curl -fsS http://localhost:3002/health || true
test -f ~/.openclaw/openclaw.json && echo "openclaw.json OK" || echo "openclaw.json MISSING"
grep -E "AGENTEC_STACK_CONFIG_DIR|AGENTEC_GRAPH_TOKEN_STORE_DIR|AGENTEC_MCP_AUTH_TOKEN" .env
./scripts/healthcheck.sh
```

Si alguno falla, usa la sección de preguntas y respuestas de abajo para aplicar la corrección puntual.

### 1) `docker: command not found`
**P:** ¿Por qué no existe `docker`?
**R:** Docker no está instalado o no está en PATH. Instala Docker Engine/Desktop y vuelve a abrir sesión.

### 2) `docker compose: command not found`
**P:** ¿Por qué no funciona `docker compose`?
**R:** Falta el plugin Compose. Actualiza Docker Desktop o instala el plugin oficial.

### 3) `permission denied while trying to connect to Docker daemon`
**P:** ¿Por qué Docker pide permisos?
**R:** En Linux/WSL, agrega tu usuario al grupo `docker` y reinicia sesión (`newgrp docker`).

### 4) `Cannot connect to the Docker daemon`
**P:** ¿Por qué no conecta al daemon?
**R:** Docker no está levantado. Inicia Docker Desktop/servicio Docker antes de ejecutar scripts.

### 5) En Windows, Docker funciona en PowerShell pero no en WSL
**P:** ¿Qué falta en WSL?
**R:** Activa integración WSL en Docker Desktop (Settings → Resources → WSL Integration).

### 6) `git: command not found`
**P:** ¿Por qué falla bootstrap al inicio?
**R:** Falta Git. Instálalo y repite `./scripts/bootstrap.sh`.

### 7) `curl: command not found`
**P:** ¿Por qué falla descarga/verificación?
**R:** Instala `curl` en tu distro (`sudo apt install curl`).

### 8) `openclaw-gateway` en restart loop con `Missing config`
**P:** ¿Qué significa?
**R:** Falta `~/.openclaw/openclaw.json` o no tiene `gateway.mode="local"`.

### 9) `EACCES` al escribir `~/.openclaw/openclaw.json`
**P:** ¿Por qué error de permisos?
**R:** El volumen montado tiene owner/permisos incorrectos. Corrige permisos del directorio en host.

### 10) `invalid spec: :/app/stack-config:ro`
**P:** ¿Qué variable falta?
**R:** `AGENTEC_STACK_CONFIG_DIR` está vacío en `.env`. Defínelo con ruta válida.

### 11) `AGENTEC_GRAPH_TOKEN_STORE_DIR` vacío
**P:** ¿Por qué falla el mount de Graph tokens?
**R:** Define `AGENTEC_GRAPH_TOKEN_STORE_DIR` y crea el directorio destino.

### 12) Warnings de `AGENTEC_MCP_AUTH_TOKEN` no definido
**P:** ¿Es obligatorio?
**R:** Sí, define un token robusto en `.env` para el MCP.

### 13) MCP responde, pero OpenClaw no ve tools
**P:** ¿Dónde está el problema?
**R:** Verifica `openclaw.json` en `mcp.servers.agentec.url` y header `Authorization`.

### 14) `MCP /health` responde 200, pero `tools/list` no trae lo esperado
**P:** ¿Qué revisar?
**R:** Revisa catálogo en `agentec-catalog/tools/approved-tools.yaml` y logs del `agentec-mcp-server`.

### 15) `Gateway /healthz` no responde y MCP sí
**P:** ¿Está mal el MCP?
**R:** No necesariamente. El problema suele ser configuración del gateway/OpenClaw.

### 16) `bootstrap.sh` termina, pero no levanta servicios
**P:** ¿Qué hago primero?
**R:** Ejecuta `docker compose ps` y luego `docker compose logs --tail=100 <service>`.

### 17) `./scripts/start.sh` falla por timeout de gateway
**P:** ¿Por qué timeout?
**R:** El gateway no completó arranque (config ausente, token inválido o error de bind).

### 18) Puerto `18789` ocupado
**P:** ¿Cómo resolver conflicto?
**R:** Cambia `OPENCLAW_GATEWAY_PORT` en `.env` y reinicia stack.

### 19) Puerto `3002` ocupado
**P:** ¿Cómo liberar MCP?
**R:** Cambia `AGENTEC_MCP_PORT` en `.env` o detén el proceso que usa ese puerto.

### 20) `node_modules/.bin/*` aparece modificado en git
**P:** ¿Debo subirlo?
**R:** No. Es ruido local/permisos; no mezclar con PR funcional.

### 21) `tsconfig` rompe build TypeScript en contenedor
**P:** ¿Por qué pasa?
**R:** Opción incompatible con versión de TS en build image. Ajusta `tsconfig` a versión real.

### 22) `profiles.json` de Graph no existe
**P:** ¿Cómo se crea?
**R:** Copia desde `profiles.example.json` o ejecuta bootstrap para autogenerarlo.

### 23) `profiles.json` de web-login no existe
**P:** ¿Cómo recuperarlo?
**R:** Copia desde `config/tools/web-login/profiles.example.json`.

### 24) API key válida pero modelo no responde
**P:** ¿Qué puede ser?
**R:** Modelo no permitido para ese proveedor, nombre incorrecto o cuota agotada.

### 25) `.env` existe pero variables no se reflejan
**P:** ¿Por qué sigue usando valores viejos?
**R:** Reinicia contenedores (`docker compose down && docker compose up -d`) para recargar env.

### 26) `healthcheck.sh` marca fail en skills
**P:** ¿Qué reviso?
**R:** Que `AGENTEC_SKILLS_DIR` apunte a carpeta correcta y exista en host.

### 27) `healthcheck.sh` marca fail en tools MCP
**P:** ¿Qué reviso?
**R:** Logs de `agentec-mcp-server` y catálogo de tools aprobadas.

### 28) Error de rutas al mezclar PowerShell y WSL
**P:** ¿Cuál es la práctica recomendada?
**R:** Ejecuta instalación/operación desde una sola shell (preferentemente WSL).

### 29) `docker compose run` funciona, `up -d` no
**P:** ¿Cómo diagnosticar?
**R:** Compara env montado con `docker compose config` y valida rutas bind.

### 30) Staging en MCP Python no refleja cambios
**P:** ¿Qué faltó?
**R:** Ejecutar `staging-switch-to-python-mcp.sh` y luego smoke/regresión.

### 31) `graph-mail` / `graph-files` devuelve auth errors
**P:** ¿Qué falta configurar?
**R:** `tenantId`, `clientId`, scopes y token store persistente en perfiles Graph.

### 32) Después de update mensual algo dejó de funcionar
**P:** ¿Cómo recupero rápido?
**R:** Corre `./scripts/healthcheck.sh`, revisa logs en `~/agentec/logs/` y reconstruye MCP si cambió catálogo.

### 33) No sé si mi instalación quedó bien
**P:** ¿Cuál es la validación mínima?
**R:** `docker compose ps` con gateway y MCP arriba + `/healthz` y `/health` respondiendo OK.


<a id="persistencia"></a>
## Persistencia

Los datos que sobreviven entre reinicios se almacenan en el host:

| Ruta en host | Montada en contenedor | Contenido |
|---|---|---|
| `~/.openclaw` | `/home/node/.openclaw` | Configuración de OpenClaw |
| `~/.openclaw/workspace` | `/home/node/.openclaw/workspace` | Workspace de agentes |
| `~/agentec/artifacts` | `/app/artifacts` | Screenshots y resultados de tools |
| `~/agentec/logs` | — | Logs operativos del stack |

<a id="repos"></a>
## Repositorios relacionados

- [agentec-catalog](../agentec-catalog) — releases y profiles aprobados
- [agentec-skills](../agentec-skills) — instrucciones de skills
- [agentec-tools](../agentec-tools) — tools ejecutables
- [openclaw/openclaw](https://github.com/openclaw/openclaw) — framework base (dependencia externa)
