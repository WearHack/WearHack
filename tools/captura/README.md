# tools/captura

Herramientas del **computador** para la calibracion de colorimetria. La app (modo
de captura de pruebas) genera el lote; esto lo comprueba y lo guarda en la boveda
cifrada. Ver [`docs/spec-modo-captura-pruebas.md`](../../docs/spec-modo-captura-pruebas.md)
y [`docs/politica-datos-colorimetria-wearhack.md`](../../docs/politica-datos-colorimetria-wearhack.md)
(seccion 12).

**Ninguna foto de calibracion va en este repositorio, ni en los tests.** Los tests de
aqui fabrican lotes sinteticos en el directorio temporal del sistema.

## `importar_lote.py`

Solo usa la libreria estandar de Python 3.

```bash
python tools/captura/importar_lote.py RUTA/lote_ab12cd34.zip
```

Que hace, en este orden:

1. **Verifica el zip sin escribir nada.** Nombres seguros (sin `..`, sin barras, ASCII, con
   la convencion `P3_LEDC_D2_R1_G_foto.jpg`), SHA-256 de cada archivo contra el
   manifiesto, el hash global, cada JSON contra el esquema 1, que cada JSON y sus dos
   archivos se correspondan, y que el contenido sea de la clase que dice el nombre
   (cabecera de PNG, JPEG o HEIC).
2. **Si algo falla, no copia nada** y cuenta todos los problemas, no solo el primero.
3. **Si todo cuadra**, copia a una carpeta temporal dentro de la boveda, vuelve a leer lo
   copiado para comprobarlo, y solo entonces la renombra. Nunca deja un destino a medias
   y nunca sobrescribe.
4. Muestra un resumen y el **hash global**. Los 8 primeros caracteres son lo que se
   teclea en la app para habilitar **Borrar**.

### Configuracion (una vez)

La ruta de la boveda va en un archivo **fuera del repositorio**. Por defecto
`~/.wearhack/importar_lote.json`, o la que diga la variable
`WEARHACK_IMPORTAR_LOTE_CONFIG`, o `--config`:

```json
{"boveda": "X:\\ruta\\de\\la\\boveda\\montada"}
```

El script se niega a leer una configuracion que este dentro de un repositorio git, y a
escribir en una boveda que lo este.

### Opciones

| Opcion | Para que |
|---|---|
| `--destino NOMBRE` | Carpeta dentro de la boveda. Por defecto, el nombre del zip sin extension. Solo letras, numeros, `.`, `-`, `_`; admite subcarpetas con `/` |
| `--config RUTA` | Otro archivo de configuracion |
| `--solo-verificar` | Comprueba el lote y muestra el hash, sin copiar nada ni leer la configuracion |

### Codigos de salida

| Codigo | Significado |
|---|---|
| 0 | Todo bien |
| 1 | El lote no paso la verificacion, o la copia fallo. **No se copio nada** |
| 2 | Uso o configuracion incorrectos |

## Formato (lo que hay que mantener de acuerdo con la app)

El script y la app son dos programas en dos lenguajes que leen el mismo formato. Para que
no se desincronicen, los dos leen **los mismos archivos de referencia, que genera la
app**, en [`ejemplos/`](ejemplos/):

- `metadatos_ejemplo.json`: el JSON de una toma.
- `manifiesto_ejemplo.json`: el manifiesto.

`client/test/paridad_con_python_test.dart` comprueba que lo que la app produce hoy es
identico a esos archivos, y `test_importar_lote.py` comprueba que el script los acepta.
Si el formato cambia a proposito:

```bash
cd client && ACTUALIZAR_GOLDEN=1 flutter test test/paridad_con_python_test.dart
```

y se revisa el diff.

**Hash global:** SHA-256 del texto formado por una linea `"<sha256>  <nombre>\n"` por
archivo (dos espacios, como `sha256sum`), ordenadas por nombre en orden ordinal. El
manifiesto no se cuenta a si mismo. Ambos lados comparten un vector de prueba con el
mismo resultado.

## Pruebas

```bash
python -m unittest discover -s tools/captura -v
```

Incluyen un fuzz con semilla fija (voltear bytes al azar de un zip valido) que exige que
el script nunca muera con un traceback.

## Lo que NO esta verificado

- Una **boveda Cryptomator real** montada: las pruebas usan una carpeta normal. El script
  renombra una carpeta dentro de la boveda y escribe con `fsync`; no se ha comprobado como
  se comporta el sistema de archivos virtual de Cryptomator con eso.
- Un lote exportado por la app **en un telefono**: el cruce se probo con el codigo real de la
  app en el computador, no con un archivo salido de un celular.
- El rendimiento con un lote completo de un celular (unos 290 MB). Con 15 tomas tarda
  fracciones de segundo.
- Rutas con acentos, o de red (`\\servidor\...`), como destino de la boveda.
