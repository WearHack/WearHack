# syntax=docker/dockerfile:1.7
#
# El contexto es gateway/, que se basta solo:
#   docker build -t wearhack/gateway .

ARG MAVEN_IMAGE=maven:3.9-eclipse-temurin-21
ARG JRE_IMAGE=eclipse-temurin:21-jre-alpine
ARG OTEL_AGENT_VERSION=2.11.0

# --------------------------------------------------------------------- build ---
FROM ${MAVEN_IMAGE} AS build
ARG OTEL_AGENT_VERSION
WORKDIR /build

COPY pom.xml ./pom.xml
COPY src ./src

RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q -DskipTests package

# El agente sale de Maven Central, el unico registro del que ya dependemos.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q dependency:copy \
      -Dartifact=io.opentelemetry.javaagent:opentelemetry-javaagent:${OTEL_AGENT_VERSION} \
      -DoutputDirectory=/opt/otel \
      -Dmdep.stripVersion=true

RUN cp target/*.jar app.jar && \
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
EXPOSE 8080

# networkaddress.cache.ttl acota cuanto cachea la JVM una resolucion DNS. En
# ECS las IPs de las tareas cambian en cada despliegue, y el gateway es el
# unico que llama a los demas por nombre: sin esto puede quedarse apuntando a
# una tarea que ya no existe. El negativo a 0 para no recordar un fallo de
# resolucion mientras un servicio todavia esta arrancando.
ENV OTEL_SERVICE_NAME=gateway \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
    OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
    OTEL_METRICS_EXPORTER=otlp \
    OTEL_LOGS_EXPORTER=none \
    SERVER_PORT=8080 \
    JAVA_TOOL_OPTIONS="-javaagent:/opt/otel/opentelemetry-javaagent.jar -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Dnetworkaddress.cache.ttl=10 -Dnetworkaddress.cache.negative.ttl=0"

HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=5 \
  CMD wget -qO- "http://127.0.0.1:${SERVER_PORT}/actuator/health/readiness" | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
