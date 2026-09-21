"""Sin telemetria en los tests.

Con el SDK activo, cada test intentaria exportar spans a un collector que no
existe y llenaria la salida de errores de conexion.
"""

import os

os.environ.setdefault("OTEL_SDK_DISABLED", "true")
