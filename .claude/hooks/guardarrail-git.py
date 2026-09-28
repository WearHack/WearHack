"""Recuerda las reglas de git a un agente que se despista.

Lo llama un hook PreToolUse sobre Bash. Recibe por stdin el JSON de la llamada
y responde con una denegacion explicada, o con nada si el comando es inocente.

El filtrado se hace aqui y no con el campo `if` del hook a proposito: ese campo
dispara con cualquier comando que use un bucle `for`, y el README del proyecto
esta lleno de bucles. Un guardarrail que salta cuando no toca acaba desactivado
por todo el mundo, que es peor que no tenerlo.

Ante cualquier duda, este script deja pasar. Su trabajo es explicar la regla,
no ser una barrera: las reglas duras viven en `permissions.deny` de
`.claude/settings.json`, que es declarativo y no depende de que esto funcione.
"""

import json
import re
import sys

# Solo cuenta si aparece en posicion de comando: al principio, tras un
# separador, o dentro de un subshell. Asi una linea que solo lo menciona,
# como `echo "no hagas git push"`, no salta.
INICIO = r"(?:^|[;&|]\s*|\(\s*|\bthen\s+|\bdo\s+)"

REGLAS = [
    (
        re.compile(INICIO + r"git\s+commit\b"),
        "En WearHack los commits los hace una persona, no el agente. Para, "
        "resume que archivos tocaste, y propon el mensaje siguiendo "
        "Conventional Commits con los scopes del monorepo. La skill "
        "preparar-commit hace exactamente eso. Ver AGENTS.md, regla 1.",
    ),
    (
        re.compile(INICIO + r"git\s+push\b"),
        "Subir el trabajo lo hace una persona. Deja los cambios listos y avisa "
        "de que se pueden subir. Ver AGENTS.md, regla 1.",
    ),
    (
        re.compile(INICIO + r"git\s+(?:checkout|switch)\s+(?:main|develop)\b"),
        "main es produccion y develop es integracion: no se trabaja sobre "
        "ellas ni se cambia de rama por cuenta propia. Di en que rama deberia "
        "ir el cambio y espera. Ver AGENTS.md, regla 2.",
    ),
    (
        re.compile(INICIO + r"git\s+reset\s+--hard\b"),
        "Ese comando tira el trabajo sin papelera. Si hace falta, que lo haga "
        "una persona que vea antes que se va a perder.",
    ),
    (
        re.compile(INICIO + r"docker\s+compose\s+down\b[^;&|]*(?:-v\b|--volumes\b)"),
        "Eso borra los volumenes: se lleva por delante los datos de Mongo y "
        "los buckets de MinIO. Usa 'docker compose down' a secas salvo que "
        "alguien pida empezar de cero. Ver AGENTS.md.",
    ),
]


def denegar(razon: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": razon,
                }
            }
        )
    )


def main() -> int:
    try:
        entrada = json.load(sys.stdin)
    except Exception:
        # Sin entrada legible no hay nada que juzgar. Dejar pasar.
        return 0

    comando = (entrada.get("tool_input") or {}).get("command") or ""

    for patron, razon in REGLAS:
        if patron.search(comando):
            denegar(razon)
            return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
