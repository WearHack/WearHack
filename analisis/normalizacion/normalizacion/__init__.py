"""Analisis de normalizacion de color para la colorimetria (issue #66).

Implementa el protocolo de `docs/protocolo-normalizacion-colorimetria.md`:
compara las tecnicas T0, T1, T2 y REF con las metricas M1-M6 sobre las fotos de
la sesion de calibracion (#65) y da un veredicto contra los criterios fijados
de antemano.

La segmentacion y el muestreo son los del servicio de Colorimetria, no una
copia: lo medido aqui es lo que el producto hara. Por eso este paquete anade al
path `services/colorimetria` (para `app.*`) y `tools/captura` (para validar los
metadatos con el mismo codigo que los importo).
"""

import sys
from pathlib import Path

RAIZ_REPO = Path(__file__).resolve().parents[3]
for _ruta in (RAIZ_REPO / "services" / "colorimetria", RAIZ_REPO / "tools" / "captura"):
    if str(_ruta) not in sys.path:
        sys.path.insert(0, str(_ruta))

SEMILLA = 42
