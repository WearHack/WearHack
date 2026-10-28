# API del modulo Usuarios (Core)

Contrato de los endpoints de las issues #10, #21 y #56. Cierra el pendiente "rutas y
contrato de los endpoints de consulta, borrado y revocacion" de la
[politica de datos](politica-datos-colorimetria-wearhack.md), seccion 14.

Base: el Core, `:8090` (no pasa por el gateway). Todo exige
`Authorization: Bearer <token de acceso de Cognito>`; solo los health checks son publicos.

**No hay identificadores de usuario en las rutas.** El usuario es siempre el `sub` del
token (`/me`), asi que no existe una peticion que alcance los datos de otra persona.

## Autenticacion

El Core es resource server: valida firma (JWKS del pool), emisor, vencimiento,
`token_use=access` y `client_id` contra `COGNITO_CLIENT_IDS`. El token de identidad se
rechaza. Ver [infra/cognito/README.md](../infra/cognito/README.md).

Sin token o con uno invalido: `401`, cabecera `WWW-Authenticate: Bearer ...` y el cuerpo
de error comun.

## Perfil (issue #10)

| Metodo | Ruta | Respuesta |
|---|---|---|
| `GET` | `/api/v1/usuarios/me` | `200` perfil. `404` si la cuenta de Cognito existe pero el registro no se completo |
| `PUT` | `/api/v1/usuarios/me` | `201` si crea el perfil, `200` si lo actualiza |
| `DELETE` | `/api/v1/usuarios/me` | `204`. Elimina la cuenta entera; ver abajo |

`PUT` recibe `{"nombre": "Ana", "mayorDeEdad": true}`. `nombre` es opcional (max. 80).
Para **crear** el perfil, `mayorDeEdad` tiene que ser `true` (`422` si no). El Core fija
la fecha de la declaracion con su reloj y no la cambia despues; `mayorDeEdad: false` sobre
un perfil existente es `422`: la declaracion no se retira, se elimina la cuenta.

```json
{
  "id": "<sub>",
  "nombre": "Ana",
  "mayorDeEdad": true,
  "mayoriaEdadDeclaradaEn": "2026-10-15T12:00:00Z",
  "creadoEn": "2026-10-15T12:00:00Z",
  "actualizadoEn": "2026-10-15T12:00:00Z"
}
```

El correo no se guarda en el Core: vive en Cognito.

## Colorimetria: consentimiento y derechos (issue #56)

| Metodo | Ruta | Respuesta |
|---|---|---|
| `POST` | `/api/v1/usuarios/me/consentimientos` | `201` nuevo, `200` si ya estaba vigente con esa version. `404` sin registro |
| `POST` | `/api/v1/usuarios/me/colorimetria` | 200 devuelve el perfil de colorimetría calculado (temporada, confianza, piel, cabello, iris, ejes y calculadoEn). Recibe directamente los bytes de una imagen PNG en el cuerpo (Content-Type: image/png), con un máximo de 5 MiB (5.242.880 bytes). Requiere autenticación JWT y consentimiento vigente para la finalidad colorimetria. El recorte recibido no se persiste. Errores: 401 sin autenticación válida, 413 si se supera el límite, 415 si el tipo de contenido no es compatible, 422 si no se cumplen las reglas de negocio (no es PNG, falta el consentimiento, o el recorte no sirve porque no tiene rostro o piel suficiente: el mensaje dice el motivo y el usuario puede repetir la foto) y 503 si el servicio de IA no está disponible; este último es reintentable. |
| `GET` | `/api/v1/usuarios/me/consentimientos` | `200` historial, del mas reciente al mas antiguo |
| `DELETE` | `/api/v1/usuarios/me/consentimientos/colorimetria` | `204` revocado. `404` si no habia uno vigente |
| `GET` | `/api/v1/usuarios/me/colorimetria` | `200` perfil derivado. `404` si no hay |
| `DELETE` | `/api/v1/usuarios/me/colorimetria` | `204`, tambien si no habia perfil |

`POST` recibe `{"finalidad": "colorimetria", "versionTexto": "2026-10-01"}`. Una version
nueva del texto deja la anterior en estado `sustituido` (re-consentimiento).

| Accion | Consentimiento | Perfil derivado | Correcciones vinculadas |
|---|---|---|---|
| Borrar perfil | sigue vigente | se borra | se quedan |
| Revocar | pasa a `revocado`, con `revocadoEn` | se borra | se borran |
| Eliminar cuenta | se borra | se borra | se borran |

Las correcciones ya desvinculadas (sin `usuario_id`) son datos agregados y no se tocan.

## Eliminar la cuenta

Orden: datos del modulo, evento `CuentaEliminada` y, al final, `AdminDeleteUser` en
Cognito. Si Cognito falla responde `502` y el usuario conserva el acceso para reintentar;
todos los pasos son idempotentes.

`closet` y `outfits` dependen de `usuarios`, no al reves: cuando tengan datos, les toca
escuchar `com.wearhack.usuarios.CuentaEliminada` y borrar lo suyo.

## Desvinculacion de correcciones (issue #57)

Tarea programada del Core (`CORRECCIONES_DESVINCULACION_CRON`, por defecto
`0 30 8 * * *` UTC, las 3:30 en Colombia). A cada correccion consumida por la recalibracion,
o vinculada hace mas de 30 dias, le quita `usuario_id` y reduce `creada_en` a
`mes` (`AAAA-MM`).

**Contrato con el job de recalibracion** (coleccion `recalibraciones`, del job; el Core
solo la lee): cada corrida deja un documento con `correcciones_hasta` (fecha). Significa
que consumio todas las correcciones con `creada_en` menor o igual. Se usa la marca mas
alta.

## Errores

Misma forma en todos, incluido el `401`:

```json
{
  "momento": "2026-10-15T12:00:00Z",
  "estado": 422,
  "error": "Unprocessable Content",
  "mensaje": "WearHack es solo para mayores de 18: hay que declarar la mayoria de edad",
  "ruta": "/api/v1/usuarios/me"
}
```
