"""Extraccion de variables de color del recorte facial.

Del recorte salen tres regiones (piel, cabello, ojos). De cada una se toma un
color representativo y de esos colores, las variables que usa el clasificador
jerarquico (respuestas A.5).

La segmentacion depende de MediaPipe y vive aparte, en `segmentacion`, para que
el muestreo y las variables se puedan probar sin modelos ni rostros.
"""
