---
name: preparar-commit
description: Prepara los commits de un cambio sin hacerlos. Agrupa lo modificado por scope, avisa de archivos que no deben commitearse, y propone mensajes en Conventional Commits validados contra las reglas de WearHack. Usala al terminar cualquier cambio, cuando pidan "haz el commit", "commitea esto" o "que mensaje pongo". En este repo los commits los hace una persona, no el agente.
---

# Preparar el commit

En WearHack **los commits los hace una persona**. Ni `git commit` ni `git push` ni
cambiar de rama: eso lo bloquean los permisos del proyecto, y no se rodea con
otro comando. Tu trabajo es dejarle a esa persona el commit **armado y revisado**,
para que solo tenga que mirarlo y pulsar el boton.

Esta skill no es un tramite. Un buen mensaje explica **por que**, y el porque solo
lo sabe quien entendio el cambio.

## 1. Mirar que hay

```bash
python .claude/skills/preparar-commit/preparar-commit.py
```

Dice la rama, agrupa los archivos por scope, y avisa de lo que no debe entrar.

- **Rama `main` o `develop`:** para. Di en que rama deberia ir el cambio y espera.
  No cambies de rama tu.
- **Aviso de scope en la rama:** solo informa. La convencion es
  `<tipo>/<scope>-<descripcion>` y el scope tiene que ser uno de la lista.
- **`NO COMMITEAR`:** `.env`, `target/`, `__pycache__`, caches, `local.properties`,
  claves. Si aparecen es que `.gitignore` no los cubre. **No los propongas**: di que
  archivos son y que hay que arreglar el `.gitignore` primero.

## 2. Entender cada grupo

El script agrupa por ruta, no por sentido. Antes de escribir nada, **lee el
diff** de cada grupo con `git diff` y los archivos nuevos. Un mensaje escrito sin
haberlo leido dice lo que hay en la lista de archivos y no lo que importa.

**Un commit por scope.** Uno solo mezclado se revisa peor y no se puede revertir
por partes. Si un scope mezcla dos ideas distintas, son dos commits aunque sea el
mismo scope.

El tipo que sugiere el script es una pista, no una decision.

## 3. Escribir cada mensaje

```
<tipo>(<scope>): <descripcion en minuscula, sin punto>

<cuerpo: el por que>
```

| | |
|---|---|
| **Tipos** | `feat`, `fix`, `chore`, `ci`, `docs`, `build`, `refactor`, `test`, `perf` |
| **Scopes** | los que lista el script: fijos (`repo`, `gateway`, `client`, `infra`, `ci`, `docs`, `agents`, `services`) mas **un scope por cada servicio** de `services/` |

Un servicio nuevo es scope valido en cuanto existe su carpeta, sin tocar nada.

**Cabecera:** hasta 72 caracteres, en minuscula, sin punto. **Sin tildes ni enes ni
flechas** en ninguna parte del mensaje: es lo que hace el historial y el validador
lo comprueba. Sin scope solo para lo transversal, como un ADR.

**Cuerpo:** explica el **por que**, no el que; el que ya esta en el diff. Que
problema resolvia, que se descarto y por que. Deja una linea en blanco tras la
cabecera.

**Se honesto con la verificacion.** Si el mensaje dice `Verificado: ...`, que sea
lo que de verdad se ejecuto. Lo que no se pudo comprobar se dice: "sin verificar
en Linux", "el APK no se construyo". Un mensaje que promete mas de lo comprobado
es peor que uno que calla.

**Coautoria:** si el sistema indica una linea `Co-Authored-By`, termina el
mensaje con ella, tal cual.

## 4. Validar

```bash
python .claude/skills/preparar-commit/preparar-commit.py --validar "<mensaje>"
```

Para un mensaje de varias lineas, guardalo en un archivo y pasa la ruta con
`--archivo`. Comprueba tipo, scope, largo, punto final, linea en blanco y que no
haya caracteres fuera de ASCII. Un `ERROR` significa que el mensaje no vale:
corrigelo antes de proponerlo. Un `aviso` es una observacion, no un bloqueo.

## 5. Proponerlo

Para cada commit, dos bloques de codigo, **uno por comando**, para que la persona
los ejecute con un clic:

```bash
git add "ruta/uno" "ruta/dos"
```

```bash
git commit -m "tipo(scope): descripcion" -m "Cuerpo del mensaje."
```

Si el cuerpo lleva `$`, comillas dobles o acentos graves, la shell los interpreta:
usa comillas simples en el segundo `-m`, o dile que use `git commit -F <archivo>`.

Explica en una frase por que van separados. Ofrece **siempre el orden**: si un
commit depende de otro, dilo.

Despues **para y espera**. No sigas con el siguiente paso hasta que la persona
confirme que hizo el commit.

## Lo que nunca propones

- `git commit --amend` sobre algo ya subido, ni `--no-verify`.
- `git push --force`, `rebase` o `reset --hard`.
- Commitear a `main` o `develop`.
- Un commit que incluya archivos del apartado `NO COMMITEAR`.
- Agrupar en uno solo cambios de scopes distintos para "ir mas rapido".
