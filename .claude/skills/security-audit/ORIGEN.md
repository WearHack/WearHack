# Origen de esta skill

Esta carpeta es una **copia sin modificar** de una skill de terceros. No la edites:
si hace falta un ajuste, hazlo en un archivo aparte o abre un cambio en el
repositorio original.

| | |
|---|---|
| Repositorio | https://github.com/cloudflare/security-audit-skill |
| Ruta copiada | `skills/security-audit/` |
| Commit | `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8` |
| Fecha del commit | 2026-09-14 |
| Licencia | MIT, en el archivo `LICENSE` de esta carpeta |
| Copiada el | 2026-09-28 |

`ORIGEN.md` es el unico archivo que no viene de Cloudflare.

## Revision antes de incorporarla

Una skill es texto que dirige a un agente dentro del repo, asi que se leyo
entera antes de copiarla. Resultado:

- **`SKILL.md` leido completo.** Es defensiva. Por defecto es solo guia: no crea
  archivos ni lanza el flujo completo sin que se pida una auditoria explicita.
- **No ejecuta git, no instala nada, no usa la red** ni manda datos a ningun
  sitio. Se busco en toda la documentacion.
- **Los dos validadores (`validate-*.cjs`) usan solo modulos internos de Node**:
  sin red, sin procesos hijos, sin escribir archivos. Los `*.test.cjs` si lanzan
  procesos, pero solo el propio validador.
- **Sus resultados se escriben fuera del repo**, en
  `~/security-audit-skill/<repo>/run-<N>`. No ensucia el arbol de git ni choca
  con la regla de no commitear.
- **Exige un sandbox del sistema operativo** para ejecutar codigo del objetivo:
  sin red, con entorno vacio y limites de recursos. Si no puede garantizarlo, no
  ejecuta nada y lo reporta como pendiente de validacion. En Windows, sin ese
  sandbox, se queda en analisis estatico.

## Limitacion conocida en Windows

**Los validadores no funcionan en Windows nativo.** `validate-findings.cjs` y
`validate-coverage-ledger.cjs` se niegan a leer un archivo si el sistema no
ofrece `O_NOFOLLOW` y `O_NONBLOCK`, y Node en Windows no los define. Fallan con
`OS no-follow and nonblocking input protection is unavailable`, incluso con un
JSON trivial. Es un fallo cerrado a proposito, no un error de esta copia.

Verificado con Node 24 en Windows 11: el suite propio de la skill da 46 pruebas
correctas, 7 fallidas y 12 omitidas. Seis de las siete fallidas muestran ese
mensaje; la septima espera codigo de salida 0 y recibe 1, coherente con la misma
causa. Los 12 omitidos los salta la propia skill en esta plataforma: incluyen
FIFO y enlaces simbolicos, pero tambien varias pruebas del CLI, como aceptar un
ledger completo. Es decir, en Windows el validador del ledger queda **sin
verificar**, no verificado.

Consecuencia: una auditoria completa lanzada desde Windows **solo puede terminar
como `run_status: "incomplete"`**, porque la fase de validacion no corre. La
guia y las revisiones acotadas no se ven afectadas, porque no usan los
validadores.

Para una auditoria completa, usar Linux, macOS o un contenedor. **Verificado en
Linux** (imagen `node:22-slim`, 2026-09-28): las 65 pruebas del suite pasan, 0
fallidas y 0 omitidas. La copia esta integra y los validadores funcionan donde el
sistema ofrece `O_NOFOLLOW` y `O_NONBLOCK`.

Para probarlo de nuevo desde Windows, con Docker corriendo, desde esta carpeta:

    docker run --rm -v "$(pwd -W):/skill:ro" -w /skill node:22-slim node --test validate-findings.test.cjs validate-coverage-ledger.test.cjs

## Cuando usarla

- **Consulta o revision acotada** ("¿es seguro este filtro?"): basta con invocarla.
- **Auditoria completa**: lanza seis fases con muchos agentes y **cuesta**. Pide
  un presupuesto maximo de invocaciones y usa el perfil `quick` para una primera
  pasada.

Zonas de WearHack donde tiene sentido:

- la autenticacion del gateway, hoy un stub, antes de desplegar nada;
- el bucket de recortes faciales, que son datos biometricos;
- la politica de confianza OIDC del rol de despliegue, que tiene que acotar
  `sub` a este repositorio.

## Actualizarla

Comparar contra el repositorio original desde el commit de arriba, revisar el
diff con el mismo cuidado que la primera vez, y actualizar este archivo con el
commit nuevo. Nunca copiar sin leer.
