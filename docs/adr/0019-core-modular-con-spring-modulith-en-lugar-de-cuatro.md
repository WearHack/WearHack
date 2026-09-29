# ADR 0019: Core modular con Spring Modulith en lugar de cuatro servicios

- **Estado:** propuesto
- **Fecha:** 2026-09-28
- **Sustituye a:** [ADR 0005](0005-servicios-de-negocio-en-spring-boot.md)

## Contexto

`usuarios`, `closet`, `outfits` y `publicidad` eran cuatro servicios identicos entre si:
un controlador de health, un test y configuracion, sin logica que justificara su
independencia y con la misma base de datos. Para seis personas que rotan, cada servicio
suma un Dockerfile, un pipeline, un puerto y un despliegue.

## Decision

Un solo deployable, el **Core**: Spring Boot con Spring Modulith, en `services/core/`,
con un puerto (8090), un Dockerfile y un pipeline.

Los modulos son `usuarios` (incluye el perfil de colorimetria, opcional), `closet`,
`outfits` y `publicidad`, mas `plataforma`, un modulo compartido para lo transversal:
salud, errores, seguridad y el cliente de la IA. Sin logica de negocio.

Las fronteras se declaran con `allowedDependencies` en el `package-info.java` de cada
modulo y se verifican con `ApplicationModules.verify()`:

| Modulo | Puede depender de |
|---|---|
| `usuarios`, `publicidad`, `plataforma` | ninguno |
| `closet` | `usuarios` |
| `outfits` | `usuarios`, `closet`, `publicidad` |

`publicidad` es el **primer candidato a extraerse** cuando el Modulith se quede corto, y
por eso su frontera esta reforzada: no puede depender de ningun otro modulo de negocio.

Los servicios de IA siguen separados: son otro lenguaje y otro ciclo de vida.

## Consecuencias

Una llamada entre modulos es una llamada de metodo, no HTTP. Un despliegue, una traza y
un proceso que vigilar.

Las fronteras estan probadas de verdad: se rompieron a proposito en una copia (importar
de un modulo prohibido, importar un tipo interno, un modulo dependiendo de otro no
declarado) y `verify()` fallo las tres veces.

**Lo que se paga:**

- **Se escala junto.** No se puede escalar `closet` sin escalar todo, y un fallo de
  memoria en un modulo tira el proceso entero.
- **La frontera es de codigo, no de datos.** Modulith verifica quien importa a quien, no
  quien lee que coleccion. Los modulos comparten Mongo y nada impide que uno lea las
  colecciones de otro. Eso depende de disciplina.
- **`verify()` solo hace cumplir lo declarado.** Quien borre el `allowedDependencies` de un
  modulo lo deja sin restricciones y `verify()` sigue en verde. Un test aparte comprueba
  que las declaraciones no se pierdan; tambien se probo borrandolas.
- **`plataforma` puede volverse un cajon de sastre.** Es el unico modulo que todos pueden
  usar sin declararlo, asi que es donde acaba lo que nadie sabe donde poner.
- **Documenter emite PlantUML, no Mermaid.** Los `.puml` generados van en `docs/modulith/`
  y se regeneran con un comando. El diagrama que se lee en GitHub sigue siendo Mermaid.

Los cuatro servicios viejos y el gateway conviven con el Core mientras dura la migracion
y se retiran cuando el Core los sustituye del todo.
