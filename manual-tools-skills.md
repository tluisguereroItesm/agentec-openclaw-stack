# Manual de Uso — Agentec Tools & Skills

## Arquitectura general

```
Tú (chat OpenClaw)
    └─► OpenClaw Gateway  :18789   (conectar con token)
            └─► Agentec MCP Server  :3002   ← 14 tools activos
                    ├─► graph_mail              (correo M365 — lectura, envío, respuesta)
                    ├─► graph_files             (archivos OneDrive/SharePoint — solo lectura)
                    ├─► graph_files_write       (subir, crear, mover, compartir archivos)
                    ├─► graph_users             (directorio de personas y equipos)
                    ├─► graph_sharepoint_search (búsqueda semántica en SharePoint)
                    ├─► graph_approvals         (aprobaciones de Power Automate)
                    ├─► graph_calendar          (calendario M365 — ver, crear, modificar)
                    ├─► graph_teams             (Teams — canales, mensajes, envío)
                    ├─► graph_flows             (Power Automate — listar, ejecutar, gestionar)
                    ├─► graph_powerbi           (Power BI — workspaces, reportes, DAX, refreshes)
                    ├─► web_login_playwright    (login web con browser)
                    ├─► web_fetch_download      (descargar documentos desde web)
                    ├─► doc_reader              (leer y resumir documentos locales)
                    └─► web_login_playwright_py (login web Python)
```

---

## Modelo conceptual — Tools y Skills

El sistema está compuesto por dos elementos distintos que trabajan juntos:

**Tool** es el ejecutor. Recibe un JSON con parámetros, llama a una API externa y devuelve un resultado estructurado. No tiene criterio propio: no sabe cuándo usarse ni qué preguntar al usuario.

**Skill** es la inteligencia del agente. Es un conjunto de instrucciones en lenguaje natural que le indica al modelo cuándo activarse, qué información solicitar si faltan datos, en qué orden llamar las tools y cómo presentar los resultados al usuario.

En flujos simples, una skill orquesta una sola tool. En flujos complejos, una skill puede encadenar múltiples tools en secuencia, usando el resultado de una como entrada para la siguiente.

---

## Permisos de Microsoft Graph configurados

La App Registration tiene los siguientes permisos delegados concedidos. Esto determina todo lo que las tools de Graph pueden hacer.

### Microsoft Graph

| Área | Permisos concedidos | Capacidades habilitadas |
|------|---------------------|------------------------|
| **Correo** | `Mail.Read`, `Mail.ReadBasic`, `Mail.ReadWrite`, `Mail.Send`, `Mail.Read.Shared`, `Mail.Send.Shared`, `Mail.ReadBasic.Shared` | Leer, buscar, enviar, responder, marcar, gestionar correos propios y compartidos |
| **Archivos** | `Files.Read`, `Files.Read.All`, `Files.ReadWrite`, `Files.ReadWrite.All` | Leer y escribir archivos en OneDrive del usuario y de otros |
| **Sitios** | `Sites.Read.All`, `Sites.ReadWrite.All`, `Sites.Manage.All` | Leer y gestionar contenido de SharePoint |
| **Usuarios** | `User.Read`, `User.Read.All`, `User.ReadBasic.All`, `User.ReadWrite.All` | Leer directorio completo de la organización, buscar personas |
| **Teams** | `Team.Create`, `Team.ReadBasic.All` | Listar y crear equipos de Microsoft Teams |
| **Identidad** | `openid`, `profile`, `email`, `offline_access` | Login, refresh token automático |

### Power Automate (Flows)

| Permisos | Capacidades |
|----------|------------|
| `Flows.Read.All`, `Flows.Manage.All` | Listar y administrar flujos de Power Automate |
| `Approvals.Read.All`, `Approvals.Manage.All` | Ver y gestionar aprobaciones |

### SharePoint (directo)

| Permisos | Capacidades |
|----------|------------|
| `AllSites.FullControl`, `AllSites.Manage` | Gestión completa de colecciones de sitios |
| `Sites.Search.All` | Búsqueda semántica en todo SharePoint |

### Power BI

| Permisos | Capacidades |
|----------|------------|
| `Report.Read.All`, `Dataset.Read.All` | Leer reportes y datasets |
| `Workspace.Read.All` | Ver workspaces |
| `Dataflow.Read.All` | Leer dataflows |

---

## Tool 1 — `graph_mail`
**¿Qué hace?** Lee, analiza, envía y gestiona correo Microsoft 365 via Microsoft Graph.

**Permisos usados:** `Mail.Read`, `Mail.ReadWrite`, `Mail.Send`, `Mail.Read.Shared`, `User.Read`, `offline_access`

### Configuración previa
Archivo: `agentec-openclaw-stack/config/tools/graph/profiles.json`
```json
{
  "profiles": {
    "default": {
      "tenantId": "5364d823-6ffb-4588-a4df-589112a1582d",
      "clientId": "d9271e49-eb16-4aa6-8bc9-00b8a42eaa0b",
      "mailScopes": ["User.Read","Mail.Read","Mail.ReadBasic","Mail.ReadWrite","Mail.Send","offline_access"]
    }
  }
}
```

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `unread` | Correos no leídos en bandeja | — |
| `recent` | Todos los correos recientes (leídos y no leídos) | — |
| `digest` | Resumen ejecutivo del buzón | `period` (`day`/`week`) |
| `search` | Búsqueda semántica con expansión de términos | `query` |
| `read` | Leer cuerpo completo de un correo | `id` |
| `send` | Enviar un correo nuevo | `to`, `subject`, `body` |
| `reply` | Responder a un correo existente | `id`, `body` |
| `mark_read` | Marcar como leído/no leído | `id`, `isRead` (bool) |
| `tasks` | Extraer tareas y fechas de correos recientes | — |
| `pending` | Correos enviados sin respuesta | — |
| `radar` | Correos de un proyecto específico | `project` |
| `suggest` | Borradores de respuesta sugeridos por IA | `id` |
| `auth-login` | Iniciar sesión (device code flow) | — |
| `auth-poll` | Completar login después de autenticar | — |

> Los aliases `list`, `all`, `inbox`, `emails` se normalizan automáticamente a la acción correcta.

### Frases de ejemplo en el chat
```
Muéstrame mis correos no leídos
Muéstrame todos los correos recientes
Dame un resumen ejecutivo de mi correo de hoy
Busca correos sobre "presupuesto Q2"
Envía un correo a juan@empresa.com con asunto "Reunión" y dile que confirmamos el lunes
Responde al correo con ID abc123 diciendo que revisaré y respondo mañana
Marca como leído el correo abc123
Extrae las tareas pendientes de mi bandeja
¿Qué correos míos están esperando respuesta?
Dame el radar del proyecto "Agentec" en los últimos 7 días
Sugiere tres respuestas para el correo abc123
```

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `profile` | Perfil de tenant | `default` |
| `top` | Cuántos correos | `20` |
| `days` | Rango de días | `7` |
| `cc` | Copia en envío | `otro@empresa.com` |
| `graphUserId` | ID de buzón alternativo | (email o GUID) |

---

## Tool 2 — `graph_files`
**¿Qué hace?** Lista, busca, lee y resume archivos de OneDrive o SharePoint.

**Permisos usados:** `Files.Read`, `Files.Read.All`, `Sites.Read.All`, `User.Read`, `offline_access`

### Configuración previa
Mismo archivo de profiles que `graph_mail`. Para SharePoint:
```json
"siteHostname": "miempresa.sharepoint.com",
"sitePath": "/sites/MiSitio",
"defaultDriveMode": "site"
```

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `recent` | Archivos recientes en OneDrive | — |
| `search` | Búsqueda por nombre o contenido | `query` |
| `read` | Extraer texto de un archivo | `id` |
| `summarize` | Leer y resumir un archivo | `id` |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Frases de ejemplo en el chat
```
Muéstrame mis archivos recientes de OneDrive
Busca documentos sobre "convenio 2026"
Lee el contenido del archivo con ID abc123
Resume el documento "Propuesta final.docx" de SharePoint
```

### Parámetros clave
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `action` | Qué hacer | `recent`, `search`, `read`, `summarize` |
| `profile` | Perfil de tenant | `default` |
| `query` | Texto a buscar | `"presupuesto"` |
| `id` | ID del archivo | (copiado del resultado de `search`) |
| `maxChars` | Límite de contenido | `5000` |
| `driveMode` | `me` o `site` | `me` |

---

## Tool 3 — `web_login_playwright`
**¿Qué hace?** Ejecuta un login en cualquier portal web y genera captura de pantalla como evidencia.

### Configuración previa
Archivo: `agentec-openclaw-stack/config/tools/web-login/profiles.json`

```json
{
  "profiles": {
    "mi-sistema": {
      "url": "https://mi-sistema.empresa.com/login",
      "usernameSelector": "#user",
      "passwordSelector": "#pass",
      "submitSelector": "button[type='submit']",
      "successIndicator": ".dashboard-header",
      "headless": true,
      "timeoutMs": 30000
    }
  }
}
```

> **¿Cómo encontrar los selectores?** En Edge/Chrome: clic derecho sobre el campo → *Inspeccionar* → copiar el `id`, `class` o atributo del elemento.

### Frases de ejemplo en el chat
```
Ejecuta el login con el perfil "mi-sistema" usando usuario=admin y password=1234
Valida que el login en https://sistema.com funciona
Haz un smoke test de login en el portal de MIAA
```

---

## Tool 4 — `web_fetch_download`
**¿Qué hace?** Navega a cualquier URL con Playwright y descarga el documento objetivo. Opcionalmente ejecuta login previo. Guarda el archivo en `artifacts/` y genera screenshot como evidencia.

### Frases de ejemplo en el chat
```
Descarga el documento PDF que está en https://portal.com/reporte.pdf
Entra al portal "mi-sistema" y descarga el reporte mensual
Baja el archivo de la página de certificados usando el botón "Descargar"
```

### Parámetros clave
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `url` | URL del archivo o página | `https://portal.com/doc.pdf` |
| `configProfile` | Perfil de login previo (opcional) | `mi-sistema` |
| `downloadSelector` | CSS del botón/enlace de descarga | `a.download-btn` |
| `waitForDownload` | Esperar evento de descarga | `true` |
| `headless` | Sin ventana visible | `true` |
| `timeoutMs` | Tiempo máximo en ms | `30000` |

---

## Tool 5 — `doc_reader`
**¿Qué hace?** Lee y extrae texto de documentos locales (PDF, DOCX, XLSX, TXT, Markdown).

### Formatos soportados
| Extensión | Librería |
|-----------|----------|
| `.pdf` | `pdfplumber` |
| `.docx` | `python-docx` |
| `.xlsx` | `openpyxl` |
| `.txt` / `.md` / `.csv` | built-in |

### Frases de ejemplo en el chat
```
Lee el contenido del archivo /app/artifacts/reporte.pdf
Extrae el texto del documento que acabé de descargar
Resume el Excel de presupuesto en /app/artifacts/presupuesto.xlsx
```

---

## Skills (cómo se activan automáticamente)

Las skills son instrucciones que OpenClaw sigue para saber **cuándo y cómo** llamar cada tool. No necesitas activarlas manualmente.

| Skill | Se activa cuando... | Tool que usa | Permisos Graph requeridos |
|-------|---------------------|--------------|--------------------------|
| `graph-mail` | Pides correos, envío, respuesta, tareas de email | `graph_mail` | `Mail.*`, `User.Read` |
| `graph-files` | Pides buscar o leer archivos de OneDrive/SharePoint | `graph_files` | `Files.*`, `Sites.Read.All` |
| `graph-files-write` | Pides subir, crear, mover, copiar o compartir archivos | `graph_files_write` | `Files.ReadWrite.All`, `Sites.ReadWrite.All` |
| `graph-users` | Buscas a alguien en la organización, manager o reportes | `graph_users` | `User.Read.All` |
| `graph-sharepoint-search` | Buscas documentos en SharePoint por tema o palabra clave | `graph_sharepoint_search` | `Sites.Search.All` |
| `graph-approvals` | Preguntas por aprobaciones pendientes o historial | `graph_approvals` | `Approvals.Read.All` |
| `graph-calendar` | Consultas agenda, creas o modificas eventos y reuniones | `graph_calendar` | `Calendars.Read`, `Calendars.ReadWrite` |
| `graph-teams` | Consultas equipos, canales o mensajes de Teams | `graph_teams` | `Team.ReadBasic.All`, `ChannelMessage.Read.All` |
| `graph-flows` | Consultas o ejecutas flujos de Power Automate | `graph_flows` | `Flows.Read.All`, `Flows.Manage.All` |
| `graph-powerbi` | Consultas reportes, dashboards o datos de Power BI | `graph_powerbi` | `Report.Read.All`, `Dataset.Read.All` |
| `web-login-monitor` | Pides validar un login, smoke test o evidencia de acceso | `web_login_playwright` | — |
| `web-document-fetch` | Pides descargar un documento desde una URL o portal web | `web_fetch_download` | — |
| `doc-summarize` | Pides leer, interpretar o resumir un documento local | `doc_reader` | — |
| `common/validacion` | Valida campos antes de ejecutar cualquier acción | (interna) | — |
| `common/notificaciones` | Formatea mensajes de éxito, error o escalamiento | (interna) | — |

---

---

## Flujos de ejemplo

### Flujo 1: Descargar y resumir un documento
```
Tu mensaje: "Descarga el reporte de https://portal.com/reporte.pdf y resúmemelo"

OpenClaw:
  1. skill web-document-fetch → web_fetch_download { url: "https://..." }
     → filePath: /app/artifacts/reporte.pdf
  2. skill doc-summarize → doc_reader { filePath: "/app/artifacts/reporte.pdf" }
     → content: "...texto...", pageCount: 12
  3. Genera resumen con el modelo
```

### Flujo 2: Correo con acción completa
```
Tu mensaje: "Lee mis correos no leídos, identifica cuáles necesitan respuesta urgente y respóndeles con un acuse de recibo"

OpenClaw:
  1. skill graph-mail → graph_mail { action: "unread" }
     → lista de correos clasificados por prioridad: CRÍTICO / ACCIÓN / INFORMATIVO
  2. Para cada correo urgente:
     graph_mail { action: "reply", id: "...", body: "Acuse de recibo..." }
```

### Flujo 3: Buscar persona y enviar correo
```
Tu mensaje: "Busca a María García en el directorio y envíale el resumen del proyecto"

OpenClaw (con skill graph-directorio + graph-mail):
  1. graph_users → busca "María García" → obtiene email
  2. graph_mail { action: "send", to: "maria@empresa.com", subject: "...", body: "..." }
```

---

## Flujo de conexión

1. Abre **http://localhost:18789/chat?session=main**
2. En **"Token de la puerta de enlace"** pega tu token del `.env`
3. Haz clic en **Conectar**
4. Escribe tu solicitud en lenguaje natural — el agente selecciona la tool correcta automáticamente

### Autenticación Microsoft Graph (primera vez)
Si el agente responde con un `AUTH_ERROR`, el flujo es automático:
1. El agente llama `auth-login` y te muestra un código de 8 caracteres
2. Abre **https://login.microsoft.com/device** e ingresa el código
3. Inicia sesión con tu cuenta de Microsoft 365
4. Regresa al chat y di "listo" — el agente completa el login con `auth-poll`
5. El token se guarda y dura 90 días con refresh automático

---

## Tool 6 — `graph_users`
**¿Qué hace?** Busca personas, lee perfiles y navega la jerarquía organizacional (manager, reportes directos) via Microsoft Graph.

**Permisos usados:** `User.Read`, `User.Read.All`, `User.ReadBasic.All`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `search` | Busca usuarios por nombre, apellido o email | `query` |
| `list` | Lista usuarios de la organización (filtrable) | — |
| `me` | Muestra el perfil del usuario autenticado | — |
| `manager` | Encuentra el manager/jefe de una persona | `query` (nombre) |
| `reports` | Lista los reportes directos de una persona | `query` (nombre) |
| `auth-login` | Iniciar sesión (device code flow) | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `query` | Nombre o email a buscar | `"María García"` |
| `department` | Filtrar por departamento (para `list`) | `"TI"` |
| `top` | Máximo de resultados | `20` |

### Frases de ejemplo en el chat
```
¿Cuál es el correo de Juan Pérez?
Busca a María García en la organización
¿Quién es mi jefe?
¿Cuáles son mis reportes directos?
Lista todos los usuarios del área de Finanzas
```

---

## Tool 7 — `graph_sharepoint_search`
**¿Qué hace?** Búsqueda semántica en todo SharePoint y OneDrive de la organización. Lista sitios disponibles.

**Permisos usados:** `Sites.Search.All`, `Sites.Read.All`, `User.Read`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `search` | Búsqueda semántica en SharePoint/OneDrive | `query` |
| `list-sites` | Lista sitios de SharePoint en la organización | — |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `query` | Texto a buscar | `"convenio ITESM 2026"` |
| `top` | Máximo de resultados | `20` |
| `contentSources` | IDs de sitios para limitar búsqueda | `["/sites/Legal"]` |

### Frases de ejemplo en el chat
```
Busca en SharePoint documentos sobre "propuesta presupuesto 2026"
Encuentra las minutas del comité directivo en SharePoint
¿Qué sitios de SharePoint existen en la organización?
Busca contratos vigentes en todos los sitios
```

> **Nota:** Para leer el contenido de un archivo encontrado, usa la tool `graph_files` con el `id` del resultado.

---

## Tool 8 — `graph_approvals`
**¿Qué hace?** Consulta aprobaciones pendientes, historial y resúmenes de Power Automate Approvals.

**Permisos usados:** `Approvals.Read.All`, `Approvals.Manage.All`, `User.Read`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `pending` | Aprobaciones pendientes de acción (default) | — |
| `all` | Todas las aprobaciones recientes con resumen por estado | — |
| `history` | Historial de aprobaciones ya completadas | — |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `top` | Máximo de resultados | `20` |

### Frases de ejemplo en el chat
```
¿Tengo aprobaciones pendientes?
Muéstrame todas mis solicitudes de aprobación
¿Cuántas aprobaciones están vencidas?
Dame el historial de aprobaciones de este mes
```

---

## Tool 9 — `graph_calendar`
**¿Qué hace?** Lee agenda, crea eventos, modifica reuniones y consulta disponibilidad en Microsoft 365 Calendar.

**Permisos usados:** `Calendars.Read`, `Calendars.ReadWrite`, `Calendars.Read.Shared`, `User.Read`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `today` | Eventos de hoy | — |
| `week` | Agenda de los próximos 7 días | — |
| `month` | Agenda del mes (30 días) | — |
| `read` | Detalle de un evento específico | `id` |
| `create` | Crear evento o reunión | `subject`, `start`, `end` |
| `update` | Modificar un evento existente | `id` |
| `delete` | Cancelar/eliminar un evento | `id` |
| `availability` | Ver slots ocupados para encontrar tiempo libre | — |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `id` | ID del evento (para read/update/delete) | — |
| `subject` | Título del evento | `"Reunión Agentec"` |
| `start` / `end` | Datetime ISO 8601 | `"2026-04-25T10:00:00"` |
| `timezone` | Zona horaria IANA | `"America/Monterrey"` |
| `body` | Descripción del evento | — |
| `location` | Lugar físico o virtual | `"Sala Monterrey"` |
| `attendees` | Lista de emails de invitados | `["ana@empresa.com"]` |
| `isOnline` | Crear como reunión de Teams | `true` |
| `days` | Días hacia adelante para availability | `5` |

### Frases de ejemplo en el chat
```
¿Qué tengo hoy en el calendario?
Muéstrame mi agenda de la semana
Crea una reunión mañana a las 10am con Juan y María sobre el sprint review
Cancela la reunión del miércoles (ID abc123)
¿Cuándo tengo tiempo libre esta semana?
Agenda una llamada de Teams el viernes a las 3pm con todo el equipo
```

---

## Tool 10 — `graph_files_write`
**¿Qué hace?** Sube, crea, renombra, mueve, copia, elimina y comparte archivos en OneDrive y SharePoint.

**Permisos usados:** `Files.ReadWrite.All`, `Sites.ReadWrite.All`, `User.Read`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `upload` | Sube un archivo local a OneDrive | `localPath`, `remotePath` |
| `create_folder` | Crea una carpeta nueva | `name` |
| `rename` | Renombra un archivo o carpeta | `id`, `name` |
| `move` | Mueve un item a otra carpeta | `id`, `destinationId` |
| `copy` | Copia un item | `id`, `destinationId` |
| `delete` | Elimina un archivo o carpeta | `id` |
| `share` | Genera enlace compartido | `id` |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `id` | ID del item (de `graph_files`) | — |
| `localPath` | Ruta local del archivo a subir | `/app/artifacts/doc.pdf` |
| `remotePath` | Ruta destino en OneDrive | `"Documents/reporte.pdf"` |
| `parent` | Carpeta padre (para create_folder) | `"Proyectos/2026"` |
| `destinationId` | ID de carpeta destino | — |
| `linkType` | `view` o `edit` | `"view"` |
| `scope` | `organization` o `anonymous` | `"organization"` |

### Frases de ejemplo en el chat
```
Sube el archivo /app/artifacts/reporte.pdf a mi OneDrive en la carpeta Proyectos/2026
Crea una carpeta "Evidencias Sprint 3" en mi OneDrive
Renombra el archivo con ID abc123 a "Propuesta Final v2.docx"
Genera un enlace compartido de solo lectura para el archivo abc123
Copia el archivo abc123 a la carpeta Archivos/2026
```

---

## Tool 11 — `graph_teams`
**¿Qué hace?** Explora Microsoft Teams: lista equipos, canales, mensajes y puede enviar mensajes a canales.

**Permisos usados:** `Team.ReadBasic.All`, `Channel.ReadBasic.All`, `ChannelMessage.Read.All`, `Chat.Read`, `User.Read`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `teams` | Lista los equipos del usuario (default) | — |
| `channels` | Lista canales de un equipo | `teamId` |
| `messages` | Mensajes recientes de un canal | `teamId`, `channelId` |
| `send_message` | Envía mensaje a un canal | `teamId`, `channelId`, `body` |
| `chats` | Lista los chats 1:1 y grupales | — |
| `members` | Miembros de un equipo | `teamId` |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `teamId` | ID del equipo (obtener con `teams`) | — |
| `channelId` | ID del canal (obtener con `channels`) | — |
| `body` | Texto del mensaje | `"Hola equipo, confirmado el sprint"` |
| `top` | Máximo de resultados | `20` |

### Frases de ejemplo en el chat
```
¿En qué equipos de Teams estoy?
Muéstrame los canales del equipo "Agentec Dev"
¿Cuáles son los últimos mensajes del canal General de Agentec?
Envía al canal General de Agentec: "Sprint review mañana a las 4pm"
¿Quiénes son los miembros del equipo de TI?
```

> **Nota de seguridad:** El agente mostrará una vista previa del mensaje antes de enviarlo y pedirá confirmación.

---

## Tool 12 — `graph_flows`
**¿Qué hace?** Lista, inspecciona y gestiona flujos de Power Automate. Puede ejecutar flujos manuales, habilitar/deshabilitar y ver historial de ejecuciones.

**Permisos usados:** `Flows.Read.All`, `Flows.Manage.All`, `User.Read`, `offline_access`

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `list` | Lista todos los flows del usuario (default) | — |
| `read` | Detalle de un flow específico | `flowId` |
| `runs` | Historial de ejecuciones de un flow | `flowId` |
| `trigger` | Ejecuta un flow manual | `flowId` |
| `enable` | Activa un flow deshabilitado | `flowId` |
| `disable` | Deshabilita un flow activo | `flowId` |
| `auth-login` | Iniciar sesión | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `flowId` | ID/nombre del flow (obtener con `list`) | — |
| `environment` | Entorno de Power Platform | `"~default"` |
| `triggerBody` | JSON de datos para trigger manual | `{"nombre": "Juan"}` |
| `top` | Máximo de resultados | `20` |

### Frases de ejemplo en el chat
```
¿Qué flujos de Power Automate tengo?
Muéstrame los flujos que fallaron esta semana
¿Está activo el flujo de notificaciones de facturación?
Ejecuta el flujo de bienvenida nuevos usuarios
Deshabilita el flujo de alertas de vacaciones
```

---

## Tool 13 — `graph_powerbi`
**¿Qué hace?** Accede a workspaces, reportes y dashboards de Power BI. Ejecuta queries DAX reales contra datasets (sin alucinaciones), abre reportes en el navegador, inspecciona páginas/tiles/esquema y gestiona refreshes.

**Permisos usados:** `https://analysis.windows.net/powerbi/api/.default`, `offline_access`

> **Importante:** Power BI usa un token de autenticación **separado** al de Microsoft Graph. El flujo de `auth-login`/`auth-poll` es el mismo, pero se debe autenticar específicamente para Power BI.

### Acciones disponibles

| Acción | Descripción | Parámetros requeridos |
|--------|-------------|----------------------|
| `workspaces` | Lista workspaces accesibles (filtrable con `search`) | — |
| `reports` | Lista/busca reportes en un workspace | `workspaceId` |
| `dashboards` | Lista/busca dashboards en un workspace | `workspaceId` |
| `datasets` | Lista datasets de un workspace | `workspaceId` |
| `schema` | Obtiene tablas, columnas y medidas de un dataset | `workspaceId`, `datasetId` |
| `query` | Ejecuta DAX y devuelve datos **reales** | `workspaceId`, `datasetId`, `dax` |
| `open` | Obtiene el URL del reporte para abrir en browser | `workspaceId`, `reportId` |
| `pages` | Lista las páginas/pestañas de un reporte | `workspaceId`, `reportId` |
| `tiles` | Lista los mosaicos de un dashboard | `workspaceId`, `dashboardId` |
| `refresh` | Historial de refreshes del dataset | `workspaceId`, `datasetId` |
| `auth-login` | Iniciar sesión (Power BI scope) | — |
| `auth-poll` | Completar login | — |

### Parámetros opcionales
| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `workspaceId` | ID del workspace (de `workspaces`) | — |
| `reportId` | ID del reporte (de `reports`) | — |
| `dashboardId` | ID del dashboard (de `dashboards`) | — |
| `datasetId` | ID del dataset (de `datasets`) | — |
| `dax` | Query DAX para `query` | ver abajo |
| `search` | Texto para filtrar workspaces/reportes/dashboards | `"Finanzas"` |
| `trigger` | `true` para lanzar refresh manual | `true` |
| `top` | Máximo de resultados | `50` |

### Flujo para responder preguntas con datos reales (sin alucinaciones)

El agente sigue estos pasos automáticamente:
```
Pregunta: "¿Cuánto vendimos en Q1 2026?"

1. workspaces → identificar workspace correcto
2. datasets con workspaceId → identificar dataset de ventas
3. schema con workspaceId + datasetId → tablas y columnas exactas
4. query con DAX:
   EVALUATE
   SUMMARIZE(
     FILTER(Sales, Sales[Quarter] = "Q1 2026"),
     "Total Ventas", SUM(Sales[Amount])
   )
5. Presenta los datos REALES devueltos — nunca inventa cifras
```

### Ejemplo de DAX
```dax
-- Ventas por mes
EVALUATE
SUMMARIZE(Sales, Sales[Month], "Total", SUM(Sales[Amount]))

-- Top 5 productos
EVALUATE
TOPN(5, SUMMARIZE(Products, Products[Name], "Revenue", SUM(Sales[Revenue])))

-- KPI simple
EVALUATE { SUM(Sales[Amount]) }
```

### Frases de ejemplo en el chat
```
¿Qué workspaces de Power BI tengo disponibles?
Muéstrame los reportes del workspace de Finanzas
¿Cuánto vendimos en el Q1 2026? (responde con datos reales)
Abre el reporte "Dashboard Ejecutivo" en el navegador
¿Cuáles son las tablas del dataset de Ventas?
Muéstrame los dashboards del workspace de Operaciones
¿Cuándo fue el último refresh del dataset de Finanzas?
Actualiza el dataset de KPIs manualmente
```

---

## Flujo de conexión (resumen)

1. Abre **http://localhost:18789/chat?session=main**
2. En **"Token de la puerta de enlace"** pega tu token del `.env`
3. Haz clic en **Conectar**
4. Escribe tu solicitud en lenguaje natural — el agente selecciona la tool correcta automáticamente
