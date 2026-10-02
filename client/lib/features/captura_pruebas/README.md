# captura_pruebas

Modo de captura para **calibrar la colorimetria** (270 fotos: 6 personas x 5 luces
x 3 celulares x 3 repeticiones). Es una herramienta interna, no una funcion del
producto. La especificacion completa esta en
[`docs/spec-modo-captura-pruebas.md`](../../../../docs/spec-modo-captura-pruebas.md).

**Estado:** esta carpeta tiene la logica (guardar, metadatos, manifiesto,
exportar, borrar). **Todavia no hay pantalla ni camara**: son el siguiente paso.
Nada de la app importa esto hoy, y un test lo comprueba.

## Reglas que no se negocian

1. **Solo builds internas.** Se activa con `--dart-define=CAPTURA_PRUEBAS=true`
   (`Configuracion.capturaPruebas`). Sin el flag el codigo no es alcanzable.
2. **Sin red.** Ningun import de red; lo comprueba `captura_pruebas_reglas_test`
   con una lista blanca de imports. Falta la comprobacion con un proxy en un
   celular real.
3. **Fuera de la galeria.** Todo va al almacenamiento privado de la app.
4. **Nunca en el repositorio.** `AlmacenCapturas` se niega a trabajar dentro de una
   carpeta con `.git` en alguno de sus padres. Los tests usan el directorio
   temporal del sistema y fotos sinteticas.
5. **Mismo recorte que el producto.** `ServicioCapturaPruebas` no recibe un recorte
   hecho por otro: recibe el `FaceCropper` y lo llama el mismo.

## Archivos

| Archivo | Que hace |
|---|---|
| `modelos.dart` | Luz, repeticion, celular, seudonimo `P1` a `P6`, e `IdToma` (el nombre de los archivos) |
| `metadatos.dart` | El JSON de cada toma (esquema 1) y `validarMetadatos`, que es estricto |
| `almacen_capturas.dart` | Guarda y lista tomas, y `verificarIntegridad` |
| `servicio_captura.dart` | Exige la autorizacion firmada, llama al recorte real y guarda |
| `lote.dart` | Manifiesto, hash global, `exportarLote` y `borrarLote` |

## Disposicion en disco

```
<raiz privada>/
  tomas/            P3_LEDC_D2_R1_G_foto.jpg   la foto tal como la dio la camara
                    P3_LEDC_D2_R1_G_recorte.png
                    P3_LEDC_D2_R1_G.json       se escribe el ultimo
  exportaciones/    lote_<8 caracteres>.zip
```

Una toma "existe" cuando existe su `.json`. La foto **no se recodifica**: asi
conserva su perfil de color (ver `lib/core/color/`).

## Exportar y borrar

El zip es **plano** (sin carpetas) y trae `manifiesto.json`. El hash global es:

```
SHA-256 del texto formado por una linea  "<sha256>  <nombre>\n"  por archivo
(dos espacios, como sha256sum), ordenadas por nombre en orden ordinal.
El manifiesto no se cuenta a si mismo.
```

`importar_lote.py` calcula lo mismo y lo muestra. **Borrar** pide los 8 primeros
caracteres de ese hash, y se compara contra el hash del **estado actual**, no del
ultimo zip: si se tomo una foto despues de exportar, el prefijo ya no vale y no se
pierde nada sin importar. Despues de borrar se comprueba que no quede ningun
archivo, y si queda alguno se dice cual.

## Decisiones que la spec no fijaba

- `rostro.bbox` es `[izquierda, arriba, derecha, abajo]` en pixeles de la foto
  completa y orientada (el orden de `Rect`). La spec no dice el orden.
- La extension de la foto puede ser `jpg` o `heic`.
- El JSON no guarda los controles de calidad del recorte ni `margenSuperiorPx`: se
  pueden recalcular desde la foto y el recorte.
