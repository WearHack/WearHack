# syntax=docker/dockerfile:1.7
#
# Se construye con el contexto en services/, no en services/closet/, porque
# el modulo necesita ver el pom padre:
#   docker build -f closet/Dockerfile -t wearhack/closet .
#
# En compose esto es:
#   build: { context: ./services, dockerfile: closet/Dockerfile }

ARG MAVEN_IMAGE=maven:3.9-eclipse-temurin-21
ARG JRE_IMAGE=eclipse-temurin:21-jre-alpine
ARG OTEL_AGENT_VERSION=2.11.0

# --------------------------------------------------------------------- build ---
FROM ${MAVEN_IMAGE} AS build
ARG SERVICIO=closet
ARG OTEL_AGENT_VERSION
WORKDIR /build

COPY pom.xml ./pom.xml
COPY ${SERVICIO} ./${SERVICIO}

# Se construye el modulo directamente y no con -pl sobre el agregador: el
# agregador exige que existan los cuatro modulos y aqui solo copiamos uno.
# Maven resuelve el pom padre por relativePath para heredar, sin mirar su
# lista de modulos.
#
# La cache de ~/.m2 sobrevive entre builds: sin esto cada cambio de una linea
# se vuelve a bajar medio Maven Central.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q -f ${SERVICIO}/pom.xml -DskipTests package

# El agente de OpenTelemetry sale de Maven Central, que es el unico registro del
# que ya dependemos. Bajarlo de GitHub Releases anadiria otro host que puede
# estar caido justo cuando toca desplegar.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q -f ${SERVICIO}/pom.xml dependency:copy \
      -Dartifact=io.opentelemetry.javaagent:opentelemetry-javaagent:${OTEL_AGENT_VERSION} \
      -DoutputDirectory=/opt/otel \
      -Dmdep.stripVersion=true

# Jar en capas. Las dependencias cambian poco y el codigo mucho, asi que
# separarlas hace que un rebuild toque solo la capa de arriba.
RUN cp ${SERVICIO}/target/*.jar app.jar && \
    java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extraido

# ------------------------------------------------------------------- runtime ---
FROM ${JRE_IMAGE} AS runtime

RUN addgroup -S wearhack && adduser -S wearhack -G wearhack
WORKDIR /app

COPY --from=build /opt/otel/opentelemetry-javaagent.jar /opt/otel/opentelemetry-javaagent.jar
COPY --from=build --chown=wearhack:wearhack /build/extraido/dependencies/ ./
COPY --from=build --chown=wearhack:wearhack /build/extraido/spring-boot-loader/ ./
COPY --from=build --chown=wearhack:wearhack /build/extraido/snapshot-dependencies/ ./
COPY --from=build --chown=wearhack:wearhack /build/extraido/application/ ./

USER wearhack
EXPOSE 8082

# El endpoint real lo fija compose; estos son los valores por defecto para que
# la imagen funcione suelta.
ENV OTEL_SERVICE_NAME=closet \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
    OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
    OTEL_METRICS_EXPORTER=otlp \
    OTEL_LOGS_EXPORTER=none \
    SERVER_PORT=8082 \
    JAVA_TOOL_OPTIONS="-javaagent:/opt/otel/opentelemetry-javaagent.jar -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=5 \
  CMD wget -qO- "http://127.0.0.1:${SERVER_PORT}/actuator/health/readiness" | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
