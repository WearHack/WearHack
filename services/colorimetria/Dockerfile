# syntax=docker/dockerfile:1.7
#
# El contexto es el del propio servicio:
#   docker build -t wearhack/colorimetria .

ARG PYTHON_IMAGE=python:3.12-slim

# --------------------------------------------------------------------- build ---
# Python 3.12 y no 3.14: MediaPipe y parte del stack numerico que este servicio
# necesita todavia no publican ruedas estables para 3.14.
FROM ${PYTHON_IMAGE} AS build

# uv en vez de pip: instala las dependencias en una fraccion del tiempo, y esto
# corre en cada push de CI.
RUN pip install --no-cache-dir uv==0.5.11

WORKDIR /build
ENV UV_PROJECT_ENVIRONMENT=/opt/venv

# Solo el pyproject: asi la capa de dependencias se reaprovecha mientras no
# cambien, por mucho que cambie el codigo.
COPY pyproject.toml ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /opt/venv && \
    uv pip install --python /opt/venv/bin/python -r pyproject.toml

# ------------------------------------------------------------------- modelos ---
# Los dos modelos oficiales de MediaPipe (Apache 2.0) con los que se calibraron
# los centroides. Por version fija y con checksum: si Google cambia el archivo,
# la imagen no construye, en vez de segmentar distinto sin avisar. El servicio
# vuelve a comprobar el hash contra el del artefacto de centroides.
FROM scratch AS modelos
ADD --chmod=644 --checksum=sha256:64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff \
    https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task \
    /modelos/face_landmarker.task
ADD --chmod=644 --checksum=sha256:c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0 \
    https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite \
    /modelos/selfie_multiclass_256x256.tflite

# ------------------------------------------------------------------- runtime ---
FROM ${PYTHON_IMAGE} AS runtime

# MediaPipe trae OpenCV completo, no el headless, y OpenCV carga libGL y glib
# al importarse aunque nunca abra una ventana. Las tareas de MediaPipe, ademas,
# cargan EGL y GLES al crear el interprete, aunque corran en CPU.
RUN apt-get update && \
    apt-get install -y --no-install-recommends libgl1 libglib2.0-0 libegl1 libgles2 && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /usr/sbin/nologin wearhack
WORKDIR /app

COPY --from=build /opt/venv /opt/venv
COPY --from=modelos /modelos /opt/modelos
COPY --chown=wearhack:wearhack app ./app

USER wearhack
EXPOSE 8091

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    SERVICIO=colorimetria \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
    SERVER_PORT=8091 \
    RUTA_MODELOS=/opt/modelos

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD python -c "import urllib.request,os,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.environ['SERVER_PORT']+'/health').status==200 else 1)"

# uvloop y httptools los trae uvicorn[standard]: menos latencia por peticion
# que el bucle de eventos por defecto.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${SERVER_PORT} --loop uvloop --http httptools --no-access-log"]
