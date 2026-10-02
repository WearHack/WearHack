# Guía Operativa — Repositorio y Gobernanza GitHub (WearHack)

_Última actualización: 2026-09-28_

Guía de flujo de equipo — separada del stack tecnológico porque describe cómo se organiza el trabajo, no decisiones de arquitectura del producto.

## Contexto

Equipo de 6 personas, generalistas (rotan entre mobile, backend Java, IA Python), con Ivan como líder. Repos privados, dentro de una GitHub Organization propia del proyecto (no bajo cuenta personal).

## Decisión: Monorepo

Con generalistas rotando entre servicios, fragmentar en un repo por servicio agrega fricción de navegación sin beneficio real de aislamiento — nadie tiene un área fija que proteger de las demás. El monorepo mantiene cambios que cruzan mobile + backend, o backend + IA, en un solo PR en vez de forzarlos a coordinarse entre repos.

## Estructura

```
wearhack/                    (GitHub Organization, privado)
├── client/                    # Flutter — mobile + web, un solo proyecto
├── services/
│   ├── core/                  # Spring Boot, monolito modular (Spring Modulith)
│   │   └── src/main/java/com/wearhack/   # paquete raíz; un subpaquete por módulo · puerto 8090
│   │       ├── usuarios/       # módulo: perfil, vínculo Cognito, perfil de colorimetría
│   │       ├── closet/         # módulo: prendas, correcciones, centroides de color de prenda
│   │       ├── outfits/        # módulo
│   │       └── publicidad/     # módulo (primer candidato a extraerse a servicio)
│   ├── colorimetria/           # FastAPI
│   └── recomendacion/          # FastAPI
├── infra/                     # lab/: docker-compose y scripts del host EC2 del Learner Lab · objetivo/: IaC de la cuenta propia (futuro)
├── docs/                       # decisiones de arquitectura, MCP.md, diagramas Mermaid
├── .github/
│   ├── workflows/               # GitHub Actions, path-filtered por servicio (ya definido en stack)
│   └── CODEOWNERS
└── docker-compose.yml           # levantar todo localmente
```

No hay build unificado entre Java/Python/Dart — `services/core` (Gradle/Maven), cada servicio de IA (pip/poetry) y `client/` (pub) se construyen con su propio tooling. Lo que comparte el monorepo es historial de PRs y versión, no el sistema de build. Hay tres pipelines de servicio (`core`, `colorimetria`, `recomendacion`) más el de mobile, cada uno filtrado por paths.

La estructura sigue la del repositorio (decidido 2026-10-01): `client/` en la raíz y paquete raíz `com.wearhack`. Las rutas de los servicios (`services/...`) se ajustan a las reales del repositorio. Un paquete compartido bajo `com.wearhack` (configuración técnica, utilidades) se declara explícitamente como módulo compartido de Spring Modulith.

## Gobernanza sin fragmentar repos

- **CODEOWNERS**: mapea rutas a revisores obligatorios — ej. cualquier cambio en `infra/**` requiere aprobación de Ivan (o de quien se designe para infraestructura), sin necesidad de un repo separado para eso.
- **Fronteras entre módulos del Core**: el CI ejecuta el test de verificación de Spring Modulith; si un módulo accede a las colecciones o internals de otro, el build falla. Es la barrera que mantiene el monolito modular — obligatoria con generalistas rotando.
- **GitHub Teams** dentro de la Organización (`mobile`, `backend`, `ia`): no como dueños fijos de repos distintos, sino para que `CODEOWNERS` asigne revisores por ruta según quién esté rotando en cada área. Da casi todo el beneficio de "repo por equipo" sin el costo de coordinar 8 repos.

## Checklist de configuración

1. Crear la GitHub Organization (verificar disponibilidad del nombre, ej. `wearhack`).
2. Agregar a los 6 miembros; crear los Teams (`mobile`, `backend`, `ia`) si se quiere enrutamiento automático de revisores.
3. Crear el repo `wearhack` **privado** dentro de la Organización, con la estructura de arriba.
4. Configurar `CODEOWNERS` con las rutas críticas (mínimo: `infra/**`).
5. Revisar el GitHub Student Developer Pack / beneficios de la universidad para la Organización — el tier gratuito da 2,000 minutos de GitHub Actions/mes en repos privados, y con 6 personas empujando commits a 6+ servicios puede quedarse corto antes de lo esperado.

## Revisión futura

Si el equipo crece más allá de generalistas rotando (ej. equipos fijos con dueños claros por servicio), reevaluar split a repos separados por dominio — mismo criterio de "no fragmentar antes de que la fragmentación se justifique" ya aplicado en el resto de la arquitectura.

Lo mismo aplica dentro del Core: cuando aparezca un disparador de extracción (escalado propio, conflicto de cadencia de despliegue, equipos fijos por dominio, integración inestable), se extrae el módulo a servicio — Publicidad es la primera candidata. Ver sección 3 del documento de stack.

## Operación del entorno de laboratorio (Learner Lab)

El MVP corre en un AWS Academy Learner Lab con un solo host EC2 y docker-compose (ver sección 6 del documento de stack). Los 6 labs son cuentas AWS independientes: no comparten presupuesto ni recursos. Convención propuesta:

- **Un lab "compartido"** aloja el entorno de demos y pruebas; una persona lo tiene a su cargo. Los demás labs son sandboxes personales o entornos desechables para ensayar.
- **Ventana de prueba**, paso a paso:
  1. Quien tiene el lab compartido pulsa "Start Lab" (la sesión dura 4 horas; se renueva pulsándolo de nuevo).
  2. Arranca la instancia EC2. Con `restart: unless-stopped`, docker-compose levanta los servicios solo.
  3. Comprueba que Caddy responde por HTTPS y que el Core valida un JWT de Cognito.
  4. Ejecuta los jobs batch pendientes con `docker compose run`, a mano o por cron.
  5. Se hacen las demos o pruebas.
  6. Al terminar, se detiene la instancia (no se termina) para conservar presupuesto.
- **Presupuesto**: revisar el panel del lab al inicio de cada ventana. El presupuesto es un total, no mensual, y los recursos se eliminan al terminar el curso.
- **CI**: Actions construye y publica las imágenes; el despliegue es `docker compose pull && up` en el host, vía SSM o SSH. Si un paso necesita AWS desde CI, se usan las credenciales temporales del lab como secrets, y se refrescan en cada sesión.
- **Datos**: solo sintéticos o de integrantes del equipo mayores de 18, con consentimiento por escrito, según `politica-datos-colorimetria-wearhack.md`. Nada de datos de terceros. El recorte facial no se persiste: nunca se guarda en el host, en S3 ni en logs.
- **Acceso al host**: SSM Session Manager, con el puerto 22 cerrado (o restringido a las IPs del equipo).
- **Los secretos** (URI de Atlas y demás) van en SSM Parameter Store o en un `.env` fuera del repositorio.

Verificaciones pendientes en un lab real (Cognito con Google, IP elástica persistente, `LabRole` con SSM, certificado de Caddy): ver el documento de stack.
