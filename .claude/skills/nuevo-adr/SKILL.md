---
name: nuevo-adr
description: Crea un ADR nuevo en docs/adr/ con el siguiente numero libre, el formato de la casa y su fila en el indice, y comprueba los existentes. Usala cuando se tome una decision de arquitectura, se cambie una anterior, o alguien pregunte "por que es asi" y no haya un ADR que lo explique. Tambien para revisar que los ADR siguen bien formados.
---

# Escribir un ADR

Un ADR sirve para que dentro de seis meses alguien entienda por que algo es como
es sin tener que preguntar. Se escribe **cuando se toma la decision**, no despues.

Lo mecanico, el numero, el archivo y la fila del indice, lo hace un script para
que lo unico que quede sea lo que importa: el contenido.

No commitees ni cambies de rama: eso lo hace una persona (AGENTS.md, reglas 1 y
2). Al terminar, para y propon el mensaje con `preparar-commit`.

## 1. Mira si ya esta decidido

```bash
python .claude/skills/nuevo-adr/nuevo-adr.py --verificar
```

Ese comando comprueba los ADR existentes, y es un buen momento para leer el
indice en `docs/adr/README.md`. Si ya hay uno que decide esto:

- **Y sigues de acuerdo:** no escribas otro. Enlaza el existente.
- **Y crees que hay que cambiarlo:** escribe uno **nuevo** que lo sustituya, y
  marca el viejo como `sustituido`. Los ADR no se borran ni se reescriben.

## 2. Crearlo

```bash
python .claude/skills/nuevo-adr/nuevo-adr.py "Titulo de la decision"
```

Crea `docs/adr/NNNN-titulo-de-la-decision.md` con el siguiente numero libre y
anade su fila al indice. Nace con estado **`propuesto`**: aceptarlo es cosa de una
persona, no del agente que lo escribe.

Con `--dry-run` dice lo que haria sin escribir nada.

El titulo es la decision, no el tema: "Mongo Atlas en AWS, no DocumentDB", no
"Base de datos". Sin tildes ni enes, como los demas.

## 3. Rellenarlo

Tres secciones. **Cortos**: un ADR que no cabe en una pantalla no lo lee nadie.

**Contexto.** Una o dos frases: que situacion obliga a decidir esto. No cuentes la
historia del proyecto.

**Decision.** Lo que se decidio, en presente y sin rodeos. Si se descartaron
alternativas reales, nombralas en una linea y di por que.

**Consecuencias.** Lo que se gana **y lo que se paga**. Esto es lo que mas se
recorta y lo que mas vale. Un ADR que solo cuenta las cosas buenas no sirve
dentro de seis meses, cuando alguien necesite saber a que renuncio el equipo.
Incluye lo que queda pendiente o sin verificar si lo hay.

Otras reglas de la casa:

- Enlaza los ADR relacionados con su ruta relativa: `[ADR 0002](0002-...md)`.
- Quita los comentarios de la plantilla al rellenar. `--verificar` los detecta.
- Escribe lo que **es**, no lo que deberia ser. Un hueco conocido va como hueco.
- No inventes datos ni cifras para que suene mas firme.

## 4. Comprobar

```bash
python .claude/skills/nuevo-adr/nuevo-adr.py --verificar
```

Comprueba numeracion sin huecos, formato, estado valido, fecha, las tres
secciones, que no queden comentarios, que cada ADR tenga su fila en el indice con
el mismo estado, y que los enlaces resuelvan.

## 5. Cerrar

Resume que decision recoge el ADR y **propon** el commit con `preparar-commit`.
Sin scope: `docs: adr NNNN titulo`, o `docs(<servicio>)` si es de un servicio
concreto.

Si crees que ya esta aceptado, dilo, pero no cambies el estado tu: pasarlo a
`aceptado` en el archivo **y** en el indice lo hace la persona que decide.
