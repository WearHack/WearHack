# infra/datos — Capa de datos (MongoDB Atlas)

Issues: #40 (épica), #41 (schema de Prenda), #42 (índice ESR), #43 (`configuracion` y
`correcciones_clasificacion`), #59 (cluster y usuarios de Atlas).

> Los nombres de colecciones marcados **[PROPUESTA]** no están definidos en la documentación
> (`respuestas-claude-code.md`, `WearHack_Protocolos_Puertos.md` sección 6). Hay que confirmarlos
> con los dueños de cada módulo antes de dar por cerrado el #59.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `wearhack-mongo-setup.js` | Crea colecciones con validador `$jsonSchema`, el índice ESR y los documentos iniciales de `configuracion`. Idempotente. |
| `wearhack-mongo-test.js` | 18 pruebas de los validadores. **Solo contra una base de prueba** (`WH_DB=wearhack_test`). |
| `wearhack-mongo-verify.js` | Comprueba la base real: validadores, índice, `configuracion` y los permisos de cada usuario de Atlas. |
| `.env.example` | Nombres de las variables de entorno. Se copia a `.env` (que **no** se sube al repo). |

## Cluster

- Atlas Free (M0), AWS `us-east-1`, a nombre de Yojhan-Toro.
- Base real: `wearhack`. Base de pruebas: `wearhack_test`.
- Acceso de red: `0.0.0.0/0` **temporal**, hasta tener AWS; entonces se reemplaza por la IP elástica del host.
- Mientras tanto, solo datos sintéticos o de integrantes con consentimiento (política de datos).
- Límites del plan Free: 100 operaciones por segundo y 500 conexiones para todo el cluster. Cada servicio
  debe usar un pool pequeño (por ejemplo, 10 conexiones) y guardar en memoria su documento de `configuracion`.

## Colecciones y dueños

| Colección | Dueño | Fuente |
|---|---|---|
| `usuarios`, `consentimientos`, `correcciones_colorimetria`, `perfiles_colorimetria` | Módulo Usuarios | protocolos §6 · nombres **[PROPUESTA]** |
| `prendas`, `correcciones_clasificacion`, `centroides_color_prenda`, `ajustes_categoria_color` | Módulo Clóset | #41, #43, #58 · el tercer nombre **[PROPUESTA]** |
| `outfits`, `selecciones` | Módulo Outfits | protocolos §6 · nombres **[PROPUESTA]** |
| `catalogos_marcas` | Módulo Publicidad | protocolos §6 · **[PROPUESTA]** |
| `centroides_temporada`, `pesos_usuario`, `coocurrencia_texturas` | Servicios de IA y jobs | protocolos §6 · **[PROPUESTA]** |
| `recalibraciones` | Job de recalibración de centroides de temporada | protocolos §6 · **[PROPUESTA]** |
| `ranking_prenda_puente` | Jobs batch (Recomendación) | protocolos §6 · **[PROPUESTA]** |
| `configuracion` | Un documento por dueño: `outfits`, `colorimetria`, `closet`, `recomendacion` | #43, G.41 |

## Usuarios de Atlas y permisos

Un usuario por componente, con TLS (viene por defecto en `mongodb+srv://`).

| Usuario | Lee y escribe | Solo lee | Sin acceso |
|---|---|---|---|
| `wh_core` | `usuarios`, `consentimientos`, `correcciones_colorimetria`, `perfiles_colorimetria`, `prendas`, `correcciones_clasificacion`, `centroides_color_prenda`, `ajustes_categoria_color`, `outfits`, `selecciones`, `catalogos_marcas`, `configuracion` | `recalibraciones`, `ranking_prenda_puente` | `centroides_temporada`, `pesos_usuario`, `coocurrencia_texturas` |
| `wh_colorimetria` | — | `centroides_temporada`, `configuracion` | todo lo demás |
| `wh_recomendacion` | — | `pesos_usuario`, `coocurrencia_texturas`, `configuracion` | todo lo demás |
| `wh_jobs` | `centroides_temporada`, `pesos_usuario`, `coocurrencia_texturas`, `recalibraciones`, `ranking_prenda_puente` | `prendas`, `correcciones_clasificacion`, `correcciones_colorimetria`, `outfits`, `selecciones`, `catalogos_marcas`, `configuracion` | `usuarios`, `consentimientos`, `perfiles_colorimetria`, `centroides_color_prenda` |

### Puntos abiertos

1. **Nombres de colecciones** marcados **[PROPUESTA]**: confirmar con Carlos (Usuarios, Clóset, Outfits, Publicidad) y Camilo (IA).
2. **`configuracion`**: los usuarios de IA solo la **leen**. La documentación dice que cada componente "lee y escribe solo su
   documento", pero Atlas no restringe por documento. Aquí la escritura queda en manos del Core y del administrador.
3. Que cada servicio lea solo su documento de `configuracion` es una regla del código, no del permiso.

### Cómo crearlos en Atlas

*Database Access → Add New Database User*: autenticación por contraseña (larga, solo letras y números), quitar el
rol por defecto "Read and write to any database" y, en *Specific Privileges*, agregar una fila por colección con
el rol `readWrite` o `read`, la base `wearhack` y la colección. Los privilegios sobre colecciones que aún no existen
son válidos. La pantalla puede variar un poco según la versión de Atlas.

## Variables de entorno

Copiar `.env.example` a `.env`, completar las URIs y **no subir `.env`**. Cada contraseña se entrega en privado, y cada
componente recibe solo la suya.

## Cómo probar

Con `mongosh` y las URIs cargadas desde `.env` (PowerShell):

```powershell
# 1) Base de pruebas: validadores
$env:WH_DB = "wearhack_test"
mongosh "<URI-admin>" --username <admin> --file wearhack-mongo-setup.js
mongosh "<URI-admin>" --username <admin> --file wearhack-mongo-test.js     # esperado: TODO OK

# 2) Base real
Remove-Item Env:WH_DB
mongosh "<URI-admin>" --username <admin> --file wearhack-mongo-setup.js

# 3) Verificación final: validadores, índice, configuracion y permisos por usuario
Get-Content .env | Where-Object { $_ -match '^\s*[^#\s].*=' } | ForEach-Object {
  $k, $v = $_ -split '=', 2; Set-Item -Path "env:$($k.Trim())" -Value $v.Trim() }
mongosh --nodb --file wearhack-mongo-verify.js                              # esperado: TODO OK
```

`<URI-admin>` es la de tu usuario con acceso a todas las bases; no es ninguna de las cuatro del `.env`.
