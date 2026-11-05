# tools/demo

Herramientas para **presentar** WearHack. No son parte del producto: no se despliegan
ni las usa la app.

## `demo_colorimetria.py`

Manda una foto al servicio de Colorimetria levantado en local y abre una pagina con
el resultado: la estacion, la confianza, la segunda opcion, las probabilidades por
estacion y por capa (subtono y contraste) y los colores medidos de piel, cabello e
iris. Si la foto no sirve, muestra el 422 tal como lo veria la persona: "Repite la
foto".

Habla directo con el servicio, sin pasar por el Core: no necesita token de Cognito.
Por eso solo sirve en local.

### Dejarla lista (una vez)

1. Enciende **Docker Desktop** y levanta el servicio:

   ```bash
   docker compose up -d colorimetria
   ```

2. Comprueba que hay centroides publicados: con una imagen cualquiera sin rostro, el
   script debe responder **422**. Si responde **503 "No hay centroides vigentes"**,
   publicalos como dice `services/colorimetria/calibracion/README.md`.
3. Mira en que puerto quedo el servicio. Es 8091 por defecto, pero tu `.env` puede
   cambiarlo:

   ```bash
   docker compose port colorimetria 8091
   ```

### Usarla

Con el entorno del servicio de Colorimetria (necesita Pillow), desde la raiz del repo:

```bash
python tools/demo/demo_colorimetria.py MI_FOTO.jpg --url http://localhost:8085
```

| Opcion | Para que |
|---|---|
| `--url` | Raiz del servicio. Por defecto `http://localhost:8091` |
| `--sin-foto` | No incrusta la foto en la pagina |
| `--no-abrir` | Solo escribe la pagina, sin abrir el navegador |

La pagina se escribe en el directorio temporal del sistema (`wearhack_demo_<nombre>.html`)
y la foto no sale del computador.

### Fotos

- **Usa tu foto o la de alguien del equipo que lo autorice.** No uses imagenes de
  Deep Armocromia: son de CelebA, con licencia solo de investigacion, y son personas
  reales que no consintieron salir en una presentacion.
- La normalizacion de la luz (#66) aun no esta aplicada. **Ensaya con la luz de la
  sala**: una luz muy calida o muy fria puede mover la estacion. Si pasa en vivo, es
  justo el argumento de por que existe #66.
- Mejor luz de ventana indirecta, rostro de frente, sin maquillaje fuerte ni filtros.

### Guion sugerido

1. **"La foto no sale del telefono."** En la app: "Tu color", consentimiento, selfie.
   Se ve el recorte de ML Kit y los controles de calidad. En el producto, solo ese
   recorte viajaria al servidor (ADR 0016).
2. **"El servidor clasifica."** En el computador, este script con tu foto: estacion,
   confianza, segunda opcion y colores medidos. Despues, una imagen sin rostro: 422,
   "Repite la foto".
3. **"Que tan bien funciona y que falta."** 55,9 % en 4 estaciones (linea base
   publicada ~54 %), 70,9 % en subtono y 77,3 % en contraste, sobre 912 imagenes de
   prueba. Falta conectar la app con el Core, guardar las probabilidades para la
   paleta del recomendador y aplicar la normalizacion de luz.

### Pruebas

```bash
python -m unittest discover -s tools/demo -v
```

Solo libreria estandar y un servicio falso en `127.0.0.1`; sin fotos de personas.
