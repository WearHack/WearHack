"""Demo de colorimetria: manda una foto al servicio y muestra el resultado en una pagina.

    python tools/demo/demo_colorimetria.py FOTO [--url http://localhost:8091] [--sin-foto]

Para presentaciones, no para el producto. Habla directo con el servicio de
Colorimetria (`POST /v1/colorimetria/analizar`), sin pasar por el Core ni
pedir token: por eso solo sirve contra el servicio levantado en local.

La foto **no sale del computador**: va al servicio en `localhost` y la pagina
se escribe en el directorio temporal del sistema. En el producto, el telefono
recorta el rostro antes y solo envia ese recorte (ADR 0016); aqui se manda la
foto entera porque el servicio vuelve a encuadrar el rostro igual que con un
recorte. Usa una foto tuya o de alguien que lo autorice.

Necesita Pillow para pasar la foto a PNG (el servicio solo acepta PNG): corre
con el entorno del servicio de Colorimetria.
"""

from __future__ import annotations

import argparse
import base64
import html
import io
import json
import sys
import tempfile
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

RUTA = "/v1/colorimetria/analizar"
# Lado mayor de la foto que se envia: el servicio la reduce a 768 de todas formas.
LADO_MAXIMO = 1600

ESTACIONES = {
    "PRIMAVERA": ("Primavera", "Subtono cálido y contraste bajo: colores claros, cálidos y luminosos."),
    "VERANO": ("Verano", "Subtono frío y contraste bajo: colores suaves, fríos y empolvados."),
    "OTONO": ("Otoño", "Subtono cálido y contraste alto: colores profundos, cálidos y terrosos."),
    "INVIERNO": ("Invierno", "Subtono frío y contraste alto: colores intensos, fríos y nítidos."),
}
CLASES = {"CALIDO": "Cálido", "FRIO": "Frío", "ALTO": "Alto", "BAJO": "Bajo"}
REGIONES = (("piel", "Piel"), ("cabello", "Cabello"), ("iris", "Iris"))


# --------------------------------------------------------------------------- #
# Color: Lab D65 a sRGB, para pintar las muestras
# --------------------------------------------------------------------------- #

_BLANCO_D65 = (0.95047, 1.0, 1.08883)
_XYZ_A_RGB = (
    (3.2404542, -1.5371385, -0.4985314),
    (-0.9692660, 1.8760108, 0.0415560),
    (0.0556434, -0.2040259, 1.0572252),
)


def lab_a_hex(l_: float, a: float, b: float) -> str:
    """CIE Lab (D65) a un color sRGB '#rrggbb', recortando lo que no cabe."""
    fy = (l_ + 16) / 116
    fx, fz = fy + a / 500, fy - b / 200
    delta = 6 / 29

    def inversa(f: float) -> float:
        return f**3 if f > delta else 3 * delta**2 * (f - 4 / 29)

    xyz = [inversa(f) * w for f, w in zip((fx, fy, fz), _BLANCO_D65, strict=True)]
    canales = []
    for fila in _XYZ_A_RGB:
        lineal = max(0.0, min(1.0, sum(c * v for c, v in zip(fila, xyz, strict=True))))
        srgb = 12.92 * lineal if lineal <= 0.0031308 else 1.055 * lineal ** (1 / 2.4) - 0.055
        canales.append(round(srgb * 255))
    return "#{:02x}{:02x}{:02x}".format(*canales)


# --------------------------------------------------------------------------- #
# Servicio
# --------------------------------------------------------------------------- #


def a_png(ruta: Path) -> bytes:
    """La foto, enderezada segun el EXIF, en sRGB y reducida, como PNG."""
    from PIL import Image, ImageCms, ImageOps

    with Image.open(ruta) as original:
        imagen = ImageOps.exif_transpose(original)
        icc = original.info.get("icc_profile")
        imagen = imagen.convert("RGB")
        if icc:
            origen = ImageCms.ImageCmsProfile(io.BytesIO(icc))
            imagen = ImageCms.profileToProfile(imagen, origen, ImageCms.createProfile("sRGB"))
    imagen.thumbnail((LADO_MAXIMO, LADO_MAXIMO))
    salida = io.BytesIO()
    imagen.save(salida, format="PNG")
    return salida.getvalue()


def analizar(url: str, png: bytes, timeout: float = 30) -> tuple[int, dict]:
    """(codigo HTTP, cuerpo JSON). Un error de red se devuelve como codigo 0."""
    peticion = urllib.request.Request(
        url.rstrip("/") + RUTA, data=png, headers={"content-type": "image/png"}, method="POST"
    )
    try:
        with urllib.request.urlopen(peticion, timeout=timeout) as respuesta:
            return respuesta.status, json.load(respuesta)
    except urllib.error.HTTPError as e:
        try:
            cuerpo = json.load(e)
        except (json.JSONDecodeError, ValueError):
            cuerpo = {}
        return e.code, cuerpo
    except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
        return 0, {"detail": str(getattr(e, "reason", e))}


# --------------------------------------------------------------------------- #
# Pagina
# --------------------------------------------------------------------------- #

_ESTILO = """
:root { --fondo:#f7f5f2; --texto:#1f1d1a; --suave:#6b665e; --tarjeta:#fff; --borde:#e4dfd7;
        --acento:#7a4b2a; --barra:#d9cfc3; --aviso:#8a4b00; --aviso-fondo:#fff4e0; }
@media (prefers-color-scheme: dark) {
  :root { --fondo:#171513; --texto:#f1ede7; --suave:#a8a198; --tarjeta:#221f1c; --borde:#3a3530;
          --acento:#e0a878; --barra:#4a433c; --aviso:#ffc27a; --aviso-fondo:#3a2a14; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--fondo); color:var(--texto);
       font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 960px; margin: 0 auto; padding: 32px 16px 48px; }
h1 { font-size: 14px; letter-spacing: .08em; text-transform: uppercase; color: var(--suave); margin: 0 0 8px; }
.estacion { font-size: 56px; font-weight: 700; line-height: 1.05; margin: 0; color: var(--acento); }
.lema { color: var(--suave); margin: 8px 0 24px; max-width: 60ch; }
.rejilla { display: grid; grid-template-columns: minmax(0, 280px) 1fr; gap: 24px; align-items: start; }
@media (max-width: 680px) { .rejilla { grid-template-columns: 1fr; } .estacion { font-size: 44px; } }
.tarjeta { background: var(--tarjeta); border: 1px solid var(--borde); border-radius: 14px; padding: 20px; }
.foto img { width: 100%; border-radius: 10px; display: block; }
h2 { font-size: 15px; margin: 0 0 12px; }
.fila { display: grid; grid-template-columns: 96px 1fr 56px; gap: 10px; align-items: center; margin: 8px 0; }
.pista { background: var(--barra); border-radius: 999px; height: 12px; overflow: hidden; }
.relleno { background: var(--acento); height: 100%; border-radius: 999px; }
.valor { text-align: right; font-variant-numeric: tabular-nums; color: var(--suave); }
.elegida { font-weight: 700; }
.muestras { display: flex; gap: 16px; flex-wrap: wrap; }
.muestra { flex: 1 1 120px; }
.color { height: 72px; border-radius: 10px; border: 1px solid var(--borde); }
.color.vacio { background: repeating-linear-gradient(45deg, transparent 0 8px, var(--borde) 8px 10px); }
.etiqueta { font-weight: 600; margin-top: 8px; }
.lab { color: var(--suave); font-size: 13px; font-variant-numeric: tabular-nums; }
.capas { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
@media (max-width: 520px) { .capas { grid-template-columns: 1fr; } }
.pila { display: grid; gap: 24px; }
.aviso { background: var(--aviso-fondo); color: var(--aviso); border-radius: 10px; padding: 12px 14px; font-size: 14px; }
.pie { color: var(--suave); font-size: 13px; margin-top: 24px; }
.error .estacion { color: var(--aviso); font-size: 40px; }
"""


def _barra(nombre: str, p: float, destacada: bool) -> str:
    clase = ' class="elegida"' if destacada else ""
    return (
        f'<div class="fila"><span{clase}>{html.escape(nombre)}</span>'
        f'<div class="pista" role="img" aria-label="{html.escape(nombre)} {p:.0%}">'
        f'<div class="relleno" style="width:{p * 100:.1f}%"></div></div>'
        f'<span class="valor">{p:.0%}</span></div>'
    )


def _muestra(nombre: str, lab: dict | None) -> str:
    if not lab:
        return (
            f'<div class="muestra"><div class="color vacio"></div><div class="etiqueta">{nombre}</div>'
            '<div class="lab">No visible: no se mide ni se inventa</div></div>'
        )
    color = lab_a_hex(lab["l"], lab["a"], lab["b"])
    return (
        f'<div class="muestra"><div class="color" style="background:{color}"></div>'
        f'<div class="etiqueta">{nombre}</div>'
        f'<div class="lab">L* {lab["l"]:.1f} · a* {lab["a"]:.1f} · b* {lab["b"]:.1f}</div></div>'
    )


def _documento(titulo: str, cuerpo: str) -> str:
    return (
        '<!doctype html><html lang="es"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>{html.escape(titulo)}</title><style>{_ESTILO}</style></head>"
        f"<body><main>{cuerpo}</main></body></html>"
    )


def _foto(png: bytes | None) -> str:
    if png is None:
        return '<div class="tarjeta foto"><p class="lab">Foto oculta (--sin-foto)</p></div>'
    datos = base64.b64encode(png).decode("ascii")
    return f'<div class="tarjeta foto"><img src="data:image/png;base64,{datos}" alt="Foto analizada"></div>'


def pagina_resultado(r: dict, png: bytes | None) -> str:
    nombre, lema = ESTACIONES.get(r["temporada"], (r["temporada"], ""))
    segunda = ESTACIONES.get(r.get("segunda_opcion", ""), (r.get("segunda_opcion", ""), ""))[0]
    probs = r.get("probabilidades", {})
    estaciones = probs.get("estaciones", {})
    barras = "".join(
        _barra(ESTACIONES[e][0], estaciones.get(e, 0.0), e == r["temporada"]) for e in ESTACIONES
    )
    capas = ""
    for capa, titulo in (("subtono", "Subtono"), ("contraste", "Contraste")):
        valores = probs.get(capa, {})
        if valores:
            ganadora = max(valores, key=valores.get)
            filas = "".join(_barra(CLASES.get(c, c), p, c == ganadora) for c, p in valores.items())
            capas += f"<div><h2>{titulo}</h2>{filas}</div>"
    aviso = (
        f'<div class="aviso">{html.escape(r["experimental"])}</div>' if r.get("experimental") else ""
    )
    muestras = "".join(_muestra(titulo, r.get(clave)) for clave, titulo in REGIONES)
    cuerpo = f"""
    <h1>WearHack · Tu estación de color</h1>
    <p class="estacion">{html.escape(nombre)}</p>
    <p class="lema">{html.escape(lema)} Confianza {r["confianza"]:.0%}; segunda opción: {html.escape(segunda)}.</p>
    <div class="rejilla">
      {_foto(png)}
      <div class="pila">
        <div class="tarjeta"><h2>Probabilidad por estación</h2>{barras}</div>
        <div class="tarjeta capas">{capas}</div>
        <div class="tarjeta"><h2>Colores medidos</h2><div class="muestras">{muestras}</div></div>
        {aviso}
      </div>
    </div>
    <p class="pie">Centroides {html.escape(r.get("version_centroides", "?"))} ·
      {len(r.get("ejes", []))} variables usadas · Sin normalización de luz todavía (#66):
      una luz muy cálida o muy fría puede mover el resultado.</p>
    """
    return _documento(f"Colorimetría: {nombre}", cuerpo)


def pagina_error(codigo: int, cuerpo: dict, png: bytes | None) -> str:
    detalle = cuerpo.get("detail") or "Sin detalle"
    if isinstance(detalle, list):  # errores de validacion de FastAPI
        detalle = "; ".join(str(d.get("msg", d)) for d in detalle)
    if codigo == 422:
        titulo, ayuda = "Repite la foto", "El recorte no sirve para medir el color. En la app, la persona repetiría la foto."
    elif codigo == 503:
        titulo, ayuda = "Servicio sin centroides", (
            "Publica los centroides con app.jobs.publicar_centroides (ver services/colorimetria/calibracion/README.md)."
        )
    elif codigo == 0:
        titulo, ayuda = "No hay servicio", "¿Docker está encendido y el servicio levantado? Revisa el puerto con --url."
    else:
        titulo, ayuda = f"Error {codigo}", "Respuesta inesperada del servicio."
    pagina = f"""
    <div class="error">
      <h1>WearHack · Colorimetría</h1>
      <p class="estacion">{html.escape(titulo)}</p>
      <p class="lema">{html.escape(str(detalle))}</p>
      <div class="rejilla">{_foto(png)}<div class="aviso">{html.escape(ayuda)}</div></div>
    </div>"""
    return _documento(f"Colorimetría: {titulo}", pagina)


# --------------------------------------------------------------------------- #


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("foto", type=Path)
    parser.add_argument("--url", default="http://localhost:8091", help="Raiz del servicio de Colorimetria")
    parser.add_argument("--sin-foto", action="store_true", help="No incluir la foto en la pagina")
    parser.add_argument("--no-abrir", action="store_true", help="Solo escribir la pagina")
    args = parser.parse_args(argv)

    png = a_png(args.foto)
    codigo, cuerpo = analizar(args.url, png)
    foto = None if args.sin_foto else png
    texto = pagina_resultado(cuerpo, foto) if codigo == 200 else pagina_error(codigo, cuerpo, foto)

    destino = Path(tempfile.gettempdir()) / f"wearhack_demo_{args.foto.stem}.html"
    destino.write_text(texto, encoding="utf-8")
    if codigo == 200:
        print(f"{cuerpo['temporada']} ({cuerpo['confianza']:.0%}), segunda: {cuerpo.get('segunda_opcion')}")
    else:
        print(f"HTTP {codigo}: {cuerpo.get('detail')}")
    print(f"Pagina: {destino}")
    if not args.no_abrir:
        webbrowser.open(destino.as_uri())
    return 0 if codigo == 200 else 1


if __name__ == "__main__":
    sys.exit(principal())
