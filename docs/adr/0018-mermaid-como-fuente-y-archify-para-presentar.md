# ADR 0018: Mermaid como fuente y Archify para presentar

- **Estado:** propuesto
- **Fecha:** 2026-09-28

## Contexto

Los diagramas de [arquitectura](../arquitectura.md) estan en Mermaid y se ven
directamente en GitHub. El equipo quiere diagramas mas cuidados para entregas y
demos, y una skill de agente, Archify, genera arquitectura, flujo, secuencia,
flujo de datos y ciclo de vida como HTML autonomo e interactivo.

## Decision

**Mermaid sigue siendo la fuente** de los diagramas del repositorio. **Archify se
usa para lo que se ensena**: entregas, demos y sustentaciones.

Archify **no se copia al repo**: cada persona lo instala en su maquina, una vez.

```bash
npx skills add tt-a1i/archify -g
```

Es un paquete de Node (pide Node 18 o superior) con su propia CLI, renderers y
esquemas. El repo no tiene Node en ninguna parte, y meterlo por una herramienta de
presentacion es un mal precio.

## Consecuencias

Los diagramas que se revisan en un PR siguen siendo texto, con diff legible, y
GitHub los renderiza sin nada extra. **El HTML de Archify no se ve en GitHub**:
por eso no sustituye a Mermaid como fuente.

Un diagrama que se ensena y otro que se versiona son dos artefactos. Si la
arquitectura cambia, hay que actualizar Mermaid; el de Archify se regenera
cuando haga falta presentarlo. Un HTML generado y guardado en el repo envejece
sin que nada avise.

Cada persona instala Archify por su cuenta, asi que pueden quedarse en versiones
distintas. Se acepta: la salida es un archivo suelto, no algo que el resto del
repo consuma.

**Archify hace una peticion HTTP** para avisar de actualizaciones. Segun su
documentacion, el servidor ve la IP y la hora, y no recibe version, proyecto ni
prompts; nunca descarga ni instala nada. Se desactiva con
`ARCHIFY_UPDATE_CHECK_DISABLED=1`.

Es un proyecto de terceros con licencia MIT que se mueve muy rapido. No esta
auditado por el equipo mas alla de leer su `SKILL.md`. Antes de usarlo con algo
que no sea un diagrama de este repo, conviene revisarlo con el mismo cuidado que
cualquier dependencia.
