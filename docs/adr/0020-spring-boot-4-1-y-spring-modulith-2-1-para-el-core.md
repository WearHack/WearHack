# ADR 0020: Spring Boot 4.1 y Spring Modulith 2.1 para el Core

- **Estado:** propuesto
- **Fecha:** 2026-09-28

## Contexto

El esqueleto original uso Spring Boot 3.5.6. Segun endoflife.date, la linea 3.5 termino su
vida el 2026-06-30, la 4.0 termina el 2026-12-31 y la 4.1 el 2027-07-31. Un Core nuevo
sobre una linea sin soporte heredaria una migracion obligatoria.

## Decision

El Core va sobre **Spring Boot 4.1.1**, **Spring Modulith 2.1.1** y Java 21.

Modulith se empareja por linea con Boot. Se comprobo en los POM de Maven Central: la 2.1
se compila contra Boot 4.1, la 2.0 contra 4.0 y la 1.4 contra 3.5. Al subir Boot, sube
Modulith.

Dependencias que hubo que cambiar por la version de Boot:

- `logstash-logback-encoder` **9.0**. Segun su POM, la 8.x depende de Jackson 2
  (`com.fasterxml`) y la 9.0 de Jackson 3 (`tools.jackson`), que es el que trae Boot 4.
  Se uso la 9.0 y funciona. **No se probo la 8.x** sobre Boot 4: se descarto por el POM.
- Agente de OpenTelemetry **2.31.1** (2026-08-23). El anterior, la 2.11 (2024-12-23), es
  anterior a Spring Framework 7 (2025-11-13).

## Consecuencias

**Lo que se encontro al migrar:** se uso `spring-boot-starter-webmvc` y su pareja
`-webmvc-test`, que existen en el BOM de 4.1.1, y `AutoConfigureMockMvc` esta ahora en
`org.springframework.boot.webmvc.test.autoconfigure`. El codigo a portar era minimo, asi que
el coste fue bajo. Con logica de negocio habria sido otro asunto.

Verificado en ejecucion: el agente 2.31.1 instrumenta Tomcat con Spring 7 y los spans salen
con nombre `GET /ruta` y el atributo `http.route`, que hace falta para las metricas de
latencia por endpoint.

**Lo que se paga:**

- **Los servicios Java viejos siguen en Boot 3.5.6, sin soporte.** Es transitorio: se borran
  cuando el Core los sustituye del todo.
- **Boot saca una version cada seis meses y la 4.1 termina en julio de 2027.** Habra que
  subir antes. Elegir la 4.1 evita una migracion dentro de tres meses, no las siguientes.
- **El codificador de logs nuevo anade un campo `tags`** con `COMMONS-LOGGING`. Se observo
  en un mensaje del servlet de Spring, que pasa por commons-logging; no se comprobo cuantos
  mas lo llevan. Los servicios de Python no lo emiten. Es ruido menor, pero rompe la
  igualdad exacta de formato entre lenguajes que buscaba el
  [ADR 0012](0012-observabilidad-con-opentelemetry.md).
