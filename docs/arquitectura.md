# Arquitectura de WearHack

Diagramas as-code. Si cambian, cambian aqui, no en una imagen que nadie puede
editar.

## Vista general

Lo que hay que quedarse de este diagrama: **la clasificacion de prendas no cruza
la red**. Pasa entera en el dispositivo, y al backend solo sube la imagen ya
procesada. Ver [ADR 0002](adr/0002-clasificacion-de-prendas-on-device.md).

```mermaid
flowchart TB
    subgraph disp["Dispositivo movil"]
        direction TB
        cam["Camara"]
        u2["u2netp<br/>quita el fondo"]
        mnv["MobileNetV3-Small INT8<br/>tipo, textura, patron"]
        mlk["ML Kit<br/>recorta el rostro"]
        cam --> u2 --> mnv
        cam --> mlk
    end

    web["Navegador<br/><i>solo consulta</i>"]

    gw["gateway<br/>Spring Cloud Gateway<br/>ruteo + auth"]

    subgraph neg["Servicios de negocio · Spring Boot"]
        direction LR
        usr["usuarios"]
        clo["closet"]
        out["outfits"]
        pub["publicidad<br/><i>marcas aliadas</i>"]
    end

    subgraph ia["Servicios de IA · FastAPI"]
        direction LR
        col["colorimetria<br/>nearest-centroid"]
        rec["recomendador<br/>motor combinatorio"]
    end

    mongo[("MongoDB<br/>documentos embebidos")]
    s3[("Object storage<br/>prendas + rostros")]
    otel["OpenTelemetry<br/>Collector"]

    mnv -- "imagen sin fondo<br/>+ atributos" --> gw
    mlk -- "solo el recorte facial" --> gw
    web --> gw

    gw --> usr & clo & out & pub
    gw --> col & rec

    usr & clo & out & pub --> mongo
    col & rec --> mongo
    clo --> s3
    col --> s3

    neg -. trazas .-> otel
    ia -. trazas .-> otel
    gw -. trazas .-> otel

    classDef device fill:#e8eaf6,stroke:#3f51b5
    classDef datos fill:#e0f2f1,stroke:#00695c
    classDef obs fill:#fff3e0,stroke:#ef6c00
    class cam,u2,mnv,mlk device
    class mongo,s3 datos
    class otel obs
```

## Digitalizar una prenda

Los interpretes se cargan **de uno en uno**, no a la vez. Con los dos en memoria,
los telefonos de gama media-baja matan el proceso, y son justo los que hay que
soportar.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant D as Dispositivo
    participant G as gateway
    participant C as closet
    participant S as Object storage

    U->>D: Foto de la prenda
    D->>D: Carga u2netp
    D->>D: Quita el fondo
    D->>D: Libera u2netp
    Note over D: Nunca los dos a la vez
    D->>D: Carga el clasificador
    D->>D: Tipo, textura, patron
    D->>D: Libera el clasificador
    D->>D: Color base a Lab

    D->>G: POST prenda (imagen sin fondo + atributos)
    Note over D,G: La foto original no sale del dispositivo
    G->>C: Rutea
    C->>S: Guarda la imagen
    C->>C: Escribe el documento
    C-->>U: Prenda digitalizada
```

## Colorimetria

Es la unica parte de IA que corre en el backend. Aun asi, lo que viaja es solo
el recorte. Ver [ADR 0016](adr/0016-solo-el-recorte-facial-sale-del-dispositivo.md).

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant D as Dispositivo
    participant G as gateway
    participant K as colorimetria
    participant S as Object storage
    participant M as MongoDB

    U->>D: Selfie
    D->>D: ML Kit detecta el rostro
    D->>D: Recorta y normaliza
    D->>S: Sube SOLO el recorte
    Note over D,S: La foto completa se queda en el telefono

    D->>G: POST analisis (clave del recorte)
    G->>K: Rutea
    K->>S: Lee el recorte
    K->>M: Lee los centroides vigentes
    K->>K: Vecino mas cercano en Lab
    K-->>U: Temporada de color
```

## Los jobs nocturnos

Corren con la misma imagen del servicio y distinto comando. Ver
[ADR 0011](adr/0011-jobs-batch-como-tareas-programadas-de-ecs.md).

```mermaid
flowchart LR
    ev["EventBridge<br/>Scheduler"]

    subgraph tareas["ECS Scheduled Tasks"]
        direction TB
        j1["recalibrar_centroides<br/><i>imagen de colorimetria</i>"]
        j2["ranking_prendas_puente<br/><i>imagen de recomendador</i>"]
        j3["ajuste_preferencias<br/><i>imagen de recomendador</i>"]
    end

    corr[("correcciones<br/>clasificacion")]
    sel[("selecciones")]
    cat[("catalogos")]
    cfg[("configuracion")]

    ev --> j1 & j2 & j3
    corr --> j1 --> cfg
    cat --> j2 --> cfg
    sel --> j3 --> cfg

    j3 -. "salta a quien tenga<br/>menos de 10 selecciones" .-> j3
```

## Como se despliega

```mermaid
flowchart LR
    pr["Pull request"] --> ci["CI<br/>solo lo que cambio"]
    ci --> main["main"]
    main --> cd["CD"]
    cd -- "token OIDC" --> aws["AWS STS<br/>credenciales temporales"]
    aws --> ecr["ECR<br/>tag = SHA + latest"]
    ecr --> ecs["ECS Fargate<br/>espera estabilidad"]
    alb["ALB"] --> ecs

    classDef seg fill:#fce4ec,stroke:#c2185b
    class aws seg
```

## Puertos en local

| Servicio | Puerto |
|---|---|
| gateway | 8080 |
| usuarios | 8081 |
| closet | 8082 |
| outfits | 8083 |
| publicidad | 8084 |
| colorimetria | 8091 |
| recomendador | 8092 |
| MongoDB | 27017 |
| MinIO | 9000, consola en 9001 |
| OpenTelemetry Collector | 4317 gRPC, 4318 HTTP |

Solo el 8080 hace falta. Los demas se publican para poder depurar un servicio
suelto, no porque el cliente los use.
