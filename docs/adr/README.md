# Decisiones de arquitectura

Un archivo por decision. Cada uno dice el contexto en una linea, la decision, y
lo que se gana y se paga con ella.

Se escriben **cuando se toma la decision**, no despues. Un ADR sirve para que
dentro de seis meses alguien entienda por que algo es como es sin tener que
preguntar.

Los ADR no se borran ni se reescriben. Si una decision cambia, se escribe uno
nuevo que sustituya al anterior y se marca el viejo como sustituido.

| # | Decision | Estado |
|---|---|---|
| [0001](0001-monorepo-en-organizacion-privada.md) | Monorepo en una organizacion privada | aceptado |
| [0002](0002-clasificacion-de-prendas-on-device.md) | La clasificacion de prendas corre en el dispositivo | aceptado |
| [0003](0003-flutter-un-proyecto-tres-targets.md) | Un solo proyecto Flutter para Android, iOS y Web | aceptado |
| [0004](0004-api-gateway-con-spring-cloud-gateway.md) | Spring Cloud Gateway como entrada unica | aceptado |
| [0005](0005-servicios-de-negocio-en-spring-boot.md) | Cuatro servicios de negocio en Spring Boot | sustituido |
| [0006](0006-servicios-de-ia-en-fastapi.md) | Los servicios de IA en FastAPI | aceptado |
| [0007](0007-rest-json-entre-backend-e-ia.md) | REST/JSON entre negocio e IA | aceptado |
| [0008](0008-mongodb-con-documentos-embebidos.md) | MongoDB con atributos embebidos | aceptado |
| [0009](0009-mongodb-atlas-en-vez-de-documentdb.md) | MongoDB Atlas en AWS, no DocumentDB | aceptado |
| [0010](0010-object-storage-s3-y-minio-en-local.md) | S3 para imagenes, MinIO en local | aceptado |
| [0011](0011-jobs-batch-como-tareas-programadas-de-ecs.md) | Los jobs nocturnos viven en los servicios Python | aceptado |
| [0012](0012-observabilidad-con-opentelemetry.md) | OpenTelemetry desde el primer dia | aceptado |
| [0013](0013-terraform-para-la-infraestructura.md) | Terraform para la infraestructura | aceptado |
| [0014](0014-ci-con-path-filters-por-servicio.md) | CI construye solo lo que cambio | aceptado |
| [0015](0015-despliegue-con-federacion-oidc.md) | Despliegue a ECS con federacion OIDC | aceptado |
| [0016](0016-solo-el-recorte-facial-sale-del-dispositivo.md) | Solo el recorte facial sale del dispositivo | aceptado |
| [0017](0017-dependencias-de-python-sin-lock.md) | Dependencias de Python sin lock | **pendiente** |
| [0018](0018-mermaid-como-fuente-y-archify-para-presentar.md) | Mermaid como fuente y Archify para presentar | propuesto |
| [0019](0019-core-modular-con-spring-modulith-en-lugar-de-cuatro.md) | Core modular con Spring Modulith en lugar de cuatro servicios | propuesto |
| [0020](0020-spring-boot-4-1-y-spring-modulith-2-1-para-el-core.md) | Spring Boot 4.1 y Spring Modulith 2.1 para el Core | propuesto |
| [0021](0021-android-sin-copia-de-seguridad-automatica-en-toda-la-app.md) | Android sin copia de seguridad automatica en toda la app | propuesto |
| [0022](0022-planes-freemium-con-cuota-mensual-de-ia.md) | Planes freemium con cuota mensual de IA | propuesto |
