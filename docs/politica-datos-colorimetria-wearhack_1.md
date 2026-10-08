# Política de datos y consentimiento — Colorimetría (WearHack)

_Última actualización: 2026-10-01 · Estado: **borrador de trabajo del equipo, pendiente de validación legal**_

> Este documento recoge decisiones de diseño y una lectura del marco normativo colombiano. **No es asesoría legal.** Antes de lanzar comercialmente debe revisarlo un abogado de protección de datos (o el consultorio jurídico de la universidad).

## 1. Decisiones (2026-09-28)

| Tema | Decisión |
|---|---|
| Recorte facial | **Sin persistencia**: se procesa en memoria y se descarta. Solo se guardan los valores derivados y el resultado |
| Público objetivo del MVP | **Solo mayores de 18 años** |
| Colorimetría | **Opcional**: la app funciona sin ella |
| Finalidad | Solo calcular la temporada de color y personalizar outfits. Sin uso publicitario ni compartido con marcas aliadas sin una autorización aparte |
| Tratamiento | Recorte y valores derivados se tratan como **datos sensibles**, por prudencia |

## 2. Marco normativo (resumen, Colombia)

Lectura basada en la Ley 1581 de 2012 y en criterios recientes de la Superintendencia de Industria y Comercio (SIC):

- Los datos biométricos son datos sensibles. Fuentes legales recientes incluyen las fotografías y la biometría facial entre los datos que hay que tratar con ese cuidado.
- La autorización debe ser **previa, expresa, informada y cualificada**. Debe explicar qué se recolecta, para qué, cuánto tiempo se conserva, quién accede y por qué canales se puede consultar, reclamar o pedir la eliminación, y decir que entregarla es **voluntario**. Una autorización general no basta.
- Nadie está obligado a autorizar el tratamiento de datos sensibles, y no se puede condicionar un servicio a entregarlos (la SIC lo aplicó en 2025, Resoluciones 52185 y 16582). De ahí que la colorimetría sea opcional.
- La SIC espera una **evaluación de riesgos** antes de implementar tecnología biométrica, y medidas de seguridad acordes.
- La ley restringe el tratamiento de datos de niños y adolescentes. En el MVP se evita el problema limitando el servicio a mayores de 18 (por validar).
- Enviar datos a proveedores en el exterior (AWS, MongoDB Atlas, con servidores en EE. UU.) encaja como **transmisión internacional a un encargado**. La SIC emitió en 2025 cláusulas contractuales modelo (Circular Externa 003 de 2025). Por validar antes de lanzar.
- Matiz del equipo, sin verificar como criterio legal: el color de piel podría relacionarse con el origen racial o étnico, también categoría sensible. Por eso los valores derivados reciben el mismo cuidado que el recorte.

## 3. Inventario de datos

| Dato | Dónde nace | Dónde vive | Persistencia | Notas |
|---|---|---|---|---|
| Foto completa | Dispositivo | Solo el dispositivo | Nunca sale ni se guarda en la app | El recorte se hace on-device |
| Recorte facial normalizado | Dispositivo | En tránsito (TLS) hasta Usuarios y Colorimetría; solo memoria | **No se persiste**: ni disco, ni S3, ni logs | Sensible |
| Valores derivados: Lab de piel, cabello e iris; ejes usados; temporada; confianza | Servicio de Colorimetría | MongoDB, en el perfil de colorimetría (módulo Usuarios) | Mientras la cuenta esté activa o hasta que el usuario lo borre | Sensible por prudencia |
| Correcciones del usuario (Lab + temporada confirmada) | Módulo Usuarios | MongoDB | Se desvinculan del usuario después de usarse en la recalibración (por validar legalmente) | Alimentan el job de recalibración de centroides |
| Evidencia de consentimiento | Módulo Usuarios | MongoDB, colección `consentimientos` | Se conserva la evidencia mínima que indique el abogado | Usuario, versión del texto, fecha y hora, finalidad, estado (otorgado o revocado) |
| Declaración de mayoría de edad | Registro | Perfil de usuario | Mientras la cuenta esté activa | Casilla y fecha; una declaración simple no verifica la edad |
| Cuenta (correo, `sub`) | Registro | AWS Cognito | Mientras la cuenta esté activa | |

## 4. Flujo del recorte, paso a paso

1. **Consentimiento** en una pantalla propia, antes de abrir la cámara. Si el usuario lo omite, no hay captura.
2. **En el dispositivo**: ML Kit detecta y recorta el rostro. Los archivos temporales se borran después del envío y nada se escribe en la galería.
3. **En tránsito**: HTTPS/TLS hacia el módulo Usuarios (en el MVP del lab, TLS termina en el host con Caddy).
4. **Módulo Usuarios** valida que exista un consentimiento vigente y reenvía el recorte al servicio de Colorimetría, sin guardarlo.
5. **Colorimetría** procesa en memoria, sin archivos temporales, y devuelve los valores derivados y la temporada.
6. **Módulo Usuarios** persiste solo los valores derivados y el resultado.
7. El recorte deja de existir al terminar la petición.

## 5. Consentimiento

**Forma**: pantalla propia antes de la cámara; botón "Autorizo" (sin casilla premarcada); separada de los términos y condiciones; con opción visible de **omitir**; versionada, con re-consentimiento si cambia el texto o la finalidad.

**Contenido mínimo**:
- Qué se recolecta: un recorte de tu rostro, y a partir de él valores de color de piel, cabello y ojos.
- Para qué: solo calcular tu temporada de color y personalizar tus outfits.
- Que es un dato sensible y que entregarlo es voluntario: puedes omitirlo y seguir usando la app.
- Qué se guarda y por cuánto tiempo: el recorte no se guarda; los valores de color y el resultado se guardan mientras tu cuenta esté activa o hasta que los borres.
- Quién accede: el equipo de WearHack y los proveedores tecnológicos que actúan por cuenta de WearHack.
- Que el procesamiento se hace en servidores ubicados en Estados Unidos.
- Tus derechos: conocer, actualizar, rectificar y suprimir tus datos y revocar la autorización, y el canal para ejercerlos.
- Enlace a la política de tratamiento de información.

**Borrador de texto, solo como punto de partida para revisión legal**:

> Para calcular tu temporada de color, WearHack analizará un recorte de tu rostro y extraerá valores de color de tu piel, cabello y ojos. Estos datos son sensibles y compartirlos es voluntario: puedes omitir este paso y seguir usando la app. El recorte de tu rostro no se guarda; solo se conservan los valores de color y tu resultado, mientras tu cuenta esté activa o hasta que los borres. Los usamos únicamente para calcular tu temporada y personalizar tus outfits. El análisis se realiza en servidores ubicados en Estados Unidos. Puedes consultar, actualizar o eliminar estos datos y revocar tu autorización cuando quieras desde la app o escribiendo a [canal por definir]. Consulta nuestra política de tratamiento de información en [enlace].
>
> [ Autorizo ]  [ Omitir ]

## 6. Colorimetría opcional: requisitos técnicos

- El onboarding ofrece **omitir** la colorimetría sin perder acceso a nada más.
- El Motor de Recomendación debe funcionar **sin perfil de color** (mismo tratamiento que ya tiene la ausencia de clima o estación: el peso correspondiente simplemente no se aplica).
- Se puede ofrecer más tarde, desde el perfil, con el mismo consentimiento.

## 7. Derechos y ciclo de vida

- Endpoints propuestos (módulo Usuarios): consultar el perfil de color, borrarlo y revocar el consentimiento. Rutas exactas por definir.
- Al **revocar o borrar el perfil de color**: se elimina el perfil derivado.
- Al **eliminar la cuenta**: se elimina el perfil derivado, la cuenta en Cognito y los datos asociados.
- **Correcciones**: se desvinculan del usuario tras su uso en la recalibración, de modo que quedan como datos agregados. El mecanismo (quién las desvincula y cuándo) está por definir, porque el job de recalibración solo tiene lectura sobre esa colección.
- **Copias de seguridad**: los backups de Atlas contienen los valores derivados; la política de conservación de backups debe alinearse con estos plazos.
- **Plazos de respuesta** a consultas y reclamos: los fija la ley; confirmarlos con el abogado.

## 8. Finalidad limitada y terceros

- El perfil de color **no se comparte con marcas aliadas** ni se usa para segmentación publicitaria sin una autorización aparte. El módulo Publicidad no lo lee.
- Proveedores que tratan datos por cuenta de WearHack (encargados): AWS (Cognito, S3, cómputo) y MongoDB Atlas. Revisar sus condiciones de tratamiento y las cláusulas modelo de la SIC antes del lanzamiento comercial.

## 9. Menores de edad

En el MVP el servicio es solo para **mayores de 18**: declaración de mayoría de edad al registrarse (casilla y fecha) y así consta en los términos. Es una declaración, no una verificación. Si más adelante se quiere abrir a menores, hará falta autorización del representante legal y una revisión legal completa.

## 10. Controles técnicos

| Capa | Control |
|---|---|
| Dispositivo | Foto completa nunca sale; recorte por ML Kit; borrado de temporales tras el envío; nada en la galería |
| Tránsito | TLS en todo canal (en el MVP del lab, Caddy con certificado de Let's Encrypt) |
| Servidor | Procesamiento en memoria, sin archivos temporales |
| Registro y trazas | Sin cuerpo de la petición en logs ni en OpenTelemetry para el endpoint del recorte; sin imágenes en mensajes de error |
| Almacenamiento | Solo valores derivados, en MongoDB con cifrado en reposo por defecto de Atlas |
| Accesos | Cada colección con un único dueño; usuarios de base de datos de mínimo privilegio. En el Learner Lab todo corre con `LabRole`, una desviación aceptada solo en el lab |
| Pruebas | Las pruebas E2E automatizadas (ARTEMIS) usan rostros sintéticos o de integrantes con consentimiento; nunca datos de terceros |

## 11. Fase académica y pruebas del MVP

- Solo integrantes del equipo, **con consentimiento por escrito**, y datos aparte y borrables.
- Si las pruebas hacen parte de un trabajo académico, revisar si el comité de ética de la universidad exige consentimiento informado.
- Con estos límites, los requisitos de lanzamiento comercial de la sección 13 no bloquean las pruebas.

## 12. Conjunto de calibración y evaluación (decidido 2026-10-01)

Es un tratamiento **distinto del producto**. En el producto el recorte no se persiste; en este conjunto sí se guardan imágenes, porque si el pipeline cambia hay que poder volver a extraer los valores.

| Tema | Decisión |
|---|---|
| Finalidad | Solo calibrar y evaluar el clasificador de colorimetría. Ningún otro uso; nunca se publica |
| Quiénes | Solo integrantes del equipo **mayores de 18**, para medir la estabilidad del pipeline. No se reclutan voluntarios externos: las etiquetas de estación vienen de un dataset público (ver abajo) |
| Consentimiento | **Específico para calibración**, por escrito, aparte del de pruebas y del de la app. Indica qué se guarda (fotos o recortes, etiqueta del experto, condiciones de captura), para qué, quién accede, dónde y cuánto tiempo, y cómo pedir el borrado |
| Qué se guarda | Imágenes capturadas con la app, metadatos de captura (luz, dispositivo) y los valores derivados |
| Almacenamiento | **Decidido (2026-10-01)**: bóveda cifrada con Cryptomator sobre una carpeta institucional de la universidad (Drive u OneDrive), **fuera del repositorio**. El proveedor solo recibe archivos cifrados, que pueden quedar fuera de Colombia (se informa en el consentimiento). Acceso limitado a quienes tienen la contraseña de la bóveda |
| Conservación | Hasta el cierre de la fase del proyecto o hasta que la persona pida el borrado, lo que ocurra primero |
| Datasets públicos | **Deep Armocromia**: centroides y evaluación, solo en la fase académica (licencia de investigación; derivado de CelebA, sin uso comercial de datos derivados). **MST-E** y **Casual Conversations v2**: solo evaluación de robustez y equidad, según sus términos (por leer). Se almacenan con las mismas reglas que el resto del conjunto y se borran cuando su licencia lo exija. Detalle en `investigacion-fuentes-colorimetria.md` |
| Comité de ética | Preguntar a la universidad si las pruebas con los propios integrantes lo requieren |

## 13. Antes de un lanzamiento comercial

- Revisión legal completa de este documento y de los textos.
- Política de tratamiento de información publicada y aviso de privacidad.
- Responsable designado y canal para atender consultas, reclamos y solicitudes de supresión.
- Evaluación de riesgos del tratamiento biométrico (formato breve).
- Contratos o cláusulas con los encargados (AWS, Atlas) según la Circular Externa 003 de 2025.
- Verificar si corresponde el registro en el Registro Nacional de Bases de Datos según el tamaño de la empresa.
- Procedimiento de incidentes de seguridad, incluida la comunicación a la autoridad.
- Cuenta AWS propia (el Learner Lab no es apto para usuarios reales ni datos reales).

## 14. Pendientes abiertos

- Mecanismo de desvinculación de las correcciones (quién y cuándo).
- Rutas y contrato de los endpoints de consulta, borrado y revocación.
- Texto definitivo del consentimiento y canal de contacto.
- Política de conservación de backups en Atlas.
- Validación legal de: clasificación de los valores derivados, desvinculación de correcciones, declaración de mayoría de edad.
- Conjunto de calibración: revisión legal del consentimiento específico (borrador listo), respuesta del comité de ética, condiciones de acceso a Deep Armocromia, términos de MST-E y de Casual Conversations v2, y validación legal de la licencia de CelebA sobre datos derivados.
