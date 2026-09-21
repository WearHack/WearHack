# syntax=docker/dockerfile:1.7
#
# El contexto es el del propio servicio:
#   docker build -t wearhack/recomendador .

ARG PYTHON_IMAGE=python:3.12-slim

# --------------------------------------------------------------------- build ---
# Python 3.12 y no 3.14: el stack numerico que este servicio va a necesitar
# todavia no publica ruedas estables para 3.14.
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

# ------------------------------------------------------------------- runtime ---
FROM ${PYTHON_IMAGE} AS runtime

RUN useradd --create-home --shell /usr/sbin/nologin wearhack
WORKDIR /app

COPY --from=build /opt/venv /opt/venv
COPY --chown=wearhack:wearhack app ./app

USER wearhack
EXPOSE 8086

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    SERVICIO=recomendador \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
    SERVER_PORT=8086

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD python -c "import urllib.request,os,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.environ['SERVER_PORT']+'/health').status==200 else 1)"

# uvloop y httptools los trae uvicorn[standard]: menos latencia por peticion
# que el bucle de eventos por defecto.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${SERVER_PORT} --loop uvloop --http httptools --no-access-log"]
