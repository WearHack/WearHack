# Especificación — Modo de captura de pruebas (calibración de colorimetría)

_2026-10-01 · Para: Claude Code · Fuentes: `protocolo-normalizacion-colorimetria.md`, `politica-datos-colorimetria-wearhack.md` (sección 12), autorización de calibración firmada._

## 1. Objetivo

Capturar las 270 fotos del protocolo de normalización (6 personas × 5 luces × 3 celulares × 3 repeticiones) con la **misma cámara y el mismo pipeline de recorte del producto**, guardando cada foto con sus metadatos, sin que nada salga del celular salvo por la exportación al computador.

## 2. Reglas que no se negocian

1. **Solo builds internas.** Se activa con un flag de compilación (por ejemplo `--dart-define=CAPTURA_PRUEBAS=true`). En una build de producción el código no debe ser alcanzable ni visible.
2. **Sin red.** El modo no hace ninguna llamada a backend, S3, Atlas ni a servicios de terceros.
3. **Fuera de la galería.** Todo se guarda en el almacenamiento privado de la app.
4. **Nunca en el repositorio.** Ningún script ni test lee o escribe fotos de calibración dentro del repositorio.
5. **Mismo recorte que el producto.** El recorte se genera llamando a la misma función del cliente que usa el flujo real de colorimetría, no a una copia.

## 3. Flujo

### 3.1 Inicio de sesión de captura

- El operador elige el seudónimo (`P1` a `P6`).
- Marca la casilla **"Autorización de calibración firmada"**. Sin ella, la captura queda deshabilitada para ese seudónimo.
- Elige el código del celular: `D1` iPhone, `D2` Android gama baja, `D3` Android gama media (el reservado para la validación final). El modelo, la versión del sistema y la build de la app se registran automáticamente.
- Marca la casilla manual **"True Tone o Night Shift activos"**, porque iOS no permite leer esos ajustes.

### 3.2 Cuadrícula de progreso

Muestra las 15 combinaciones de luz y repetición para la persona en ese celular, que son 45 por persona en total sumando los tres celulares. Cada combinación aparece como pendiente o capturada, y se puede repetir una toma (la nueva reemplaza a la anterior, con confirmación).

### 3.3 Captura

- Luz: `VEN`, `LEDC`, `LEDF`, `MIX` o `BAJ`. Repetición: `R1`, `R2` o `R3`.
- Tarjeta gris: automática según la repetición. `R1` lleva tarjeta (`G`) y la app muestra el aviso "pon la tarjeta gris junto al rostro"; `R2` y `R3` no la llevan (`N`) y la app muestra el aviso "retira la tarjeta".
- Cámara frontal y flash apagado.
- **Guía de encuadre**: un óvalo y un indicador de distancia basado en el ancho del rostro que detecta ML Kit, para mantener los 30-40 cm. El rango de píxeles equivalente se calibra una vez por celular y queda en una constante por código de celular.

### 3.4 Qué se guarda por toma

| Archivo | Contenido |
|---|---|
| `P3_LEDC_D2_R1_G_foto.<ext>` | Foto completa a resolución nativa, **conservando su perfil de color** (el iPhone suele capturar en Display P3) |
| `P3_LEDC_D2_R1_G_recorte.png` | El recorte exactamente como lo enviaría el producto |
| `P3_LEDC_D2_R1_G.json` | Metadatos (sección 4) |

### 3.5 Exportar y borrar

1. **Exportar** genera un `.zip` con todas las tomas del lote y un `manifiesto.json`: la lista de archivos con su SHA-256 y un hash global del lote. Se comparte por la hoja de compartir del sistema, AirDrop o USB.
2. En el computador, `importar_lote.py` (sección 6) verifica los hashes y copia el lote a la bóveda Cryptomator.
3. **Borrar** solo se habilita después de que el operador escriba en la app los primeros 8 caracteres del hash global que muestra el script. La app borra entonces todas las tomas y comprueba que no quede ningún archivo del lote.

## 4. Esquema de metadatos (JSON)

```json
{
  "esquema": 1,
  "seudonimo": "P3",
  "luz": "LEDC",
  "repeticion": "R1",
  "tarjeta_gris": true,
  "fecha_hora": "2026-10-15T15:42:07-05:00",
  "celular": { "codigo": "D2", "modelo": "<auto>", "sistema": "<auto>", "build_app": "<auto>" },
  "pantalla": { "true_tone_o_night_shift": false },
  "camara": {
    "lente": "frontal",
    "flash": "apagado",
    "parametros": { "exposicion": null, "iso": null, "balance_blancos": null }
  },
  "rostro": { "bbox": [0, 0, 0, 0], "ancho_px": 0 },
  "perfil_color": { "foto": "<p. ej. Display P3 | sRGB>", "recorte": "<p. ej. sRGB>" },
  "archivos": {
    "foto": "P3_LEDC_D2_R1_G_foto.jpg",
    "recorte": "P3_LEDC_D2_R1_G_recorte.png",
    "sha256": { "foto": "", "recorte": "" }
  }
}
```

Los parámetros de cámara que el plugin no exponga quedan en `null`. No se inventan.

## 5. Criterios de aceptación

- [ ] En una build de producción no existe ninguna ruta, menú ni gesto que abra el modo.
- [ ] Sin la casilla de autorización marcada, el botón de captura está deshabilitado.
- [ ] Ninguna petición de red durante el modo (verificado con el inspector de red o un proxy).
- [ ] Ninguna foto aparece en la galería del celular.
- [ ] Nombres de archivo según la convención y JSON válido contra el esquema.
- [ ] En iPhone, la foto conserva su perfil ICC (comprobado con `exiftool` o equivalente), y el campo `perfil_color` coincide con el perfil real.
- [ ] El recorte guardado es idéntico, byte a byte o con un hash igual, al que produce la función del flujo real con la misma entrada (test automatizado).
- [ ] Exportar genera un zip cuyo manifiesto valida `importar_lote.py`.
- [ ] Después de Borrar no queda ningún archivo del lote en el almacenamiento de la app.

## 6. Script del computador: `importar_lote.py`

- **Entrada**: la ruta al `.zip` y la ruta de destino dentro de la bóveda Cryptomator montada (la ruta se configura en un archivo local fuera del repositorio).
- **Pasos**: verifica el SHA-256 de cada archivo contra el manifiesto, valida cada JSON contra el esquema, copia el lote al destino sin sobrescribir y muestra un resumen (tomas por persona, celular y luz) y el hash global para la confirmación en la app.
- **Fallo**: si algún hash o JSON no valida, no copia nada y lo reporta.

## 7. Fuera de alcance

- Los scripts de análisis M1 a M6 (especificación aparte).
- Las técnicas de corrección T1 a T4.
- El bloqueo nativo de exposición y balance de blancos (solo para T4, si llega a hacer falta).

## 8. Puntos técnicos a verificar y reportar (no decidir sin consultar)

1. Qué parámetros de cámara expone el plugin de Flutter en uso (exposición, ISO, modo de balance de blancos) en Android y en iOS.
2. **Si el perfil ICC sobrevive** a decodificar y recodificar en Dart al generar el recorte. Si se pierde, el recorte debe convertirse explícitamente a sRGB antes de guardarse, y `perfil_color.recorte` debe decirlo. Este es el punto de mayor riesgo para el nivel 0.
3. Formato de la foto en iOS (HEIC o JPEG) y si conviene forzar uno.
4. Manejo de la orientación EXIF en la foto y en el recorte.
5. El espacio disponible y el tiempo de exportación para un lote de 45 tomas por celular.
