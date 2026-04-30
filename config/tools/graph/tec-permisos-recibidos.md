# Permisos recibidos (tenant TEC)

## Datos de conexión aplicados localmente

- Tenant ID: `c65a3ea6-0f7c-400b-8934-5a6dc1705645`
- Client ID: `4a2a4b81-79cf-4e5d-810e-5cb4d6beb721`
- Redirect URI local:
  - `http://localhost:18789/auth/callback`
  - `http://127.0.0.1:18789/auth/callback`

> El client secret se configuró en `.env` local y no se documenta aquí por seguridad.

## Microsoft Graph (Delegated)

- `Calendars.Read`
- `Calendars.ReadWrite`
- `Channel.ReadBasic.All`
- `ChannelMessage.Read.All`
- `Chat.Read`
- `Files.Read`
- `Files.Read.All`
- `Files.ReadWrite.All`
- `Mail.Read`
- `Mail.ReadBasic`
- `Mail.Send`
- `MailboxSettings.Read`
- `Notes.Read`
- `Notes.Read.All`
- `offline_access`
- `OnlineMeetings.Read`
- `OnlineMeetingTranscript.Read.All`
- `People.Read`
- `Sites.Read.All`
- `Team.ReadBasic.All`
- `User.Read`
- `User.Read.All`

## Nota operativa

Con este set actual:
- Correo, calendario, Teams y lectura/escritura de archivos están cubiertos.
- Flows/Approvals/Power BI requieren permisos adicionales si se van a usar en ese tenant.
