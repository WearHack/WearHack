"""El paquete `normalizacion` se importa desde aqui al correr pytest en esta carpeta.

Ninguna prueba usa fotos de personas: todas fabrican imagenes y mediciones.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
