# ADR 0022: Planes freemium con cuota mensual de IA

- **Estado:** propuesto
- **Fecha:** 2026-11-05

## Contexto

Hasta ahora la unica monetizacion documentada era la de las marcas aliadas: recomendar
prendas puente de su catalogo. El modelo financiero a 36 meses del equipo
(`WearHack_Modelo_Financiero_36M.xlsm`, fuera del repo) agrega un lado B2C freemium con
tres niveles:

| Plan | Precio | Incluye |
|---|---|---|
| Gratis | 0 | ~15 solicitudes de IA al mes, closet y dress code limitados |
| Esencial | COP 6.900/mes | Closet ilimitado, plan semanal, dress code ilimitado, 30 solicitudes de IA |
| Plus | COP 12.900/mes | Lo de Esencial mas escaneo en tienda, analisis del closet y maleta |

El modelo descarta cobrar por solicitud extra al usuario final ("B2C sin overage: se
controla con limites, no con cobro extra"). El overage existe solo para las marcas. Las
marcas siguen siendo ~91% del ingreso proyectado.

## Decision

- El plan es un campo de `usuarios` (`plan`: `GRATIS`, `ESENCIAL`, `PLUS`). Un perfil sin
  el campo, creado antes de los planes, cuenta como `GRATIS`. Lo decide el Core, nunca el
  cliente: no hay endpoint para que el usuario lo cambie.
- Los derechos de cada plan viven en una sola tabla del modulo `usuarios`
  (`CatalogoPlanes`). Los demas modulos los consultan por la interfaz publica
  `PlanesUsuario` en vez de copiarlos.
- La cuota de IA es por mes calendario (hora de Colombia) y se guarda en `consumo_ia`, un
  documento por usuario y mes. Al llegar al tope se responde **429**. Se reserva con un
  upsert condicionado, asi que peticiones simultaneas no se pasan del tope.
- Una solicitud que falla (IA caida, recorte sin rostro, sin consentimiento) devuelve su
  cupo: el usuario no paga por un error que no es suyo.
- El cobro de la cuota en las rutas que llaman a la IA es un interceptor del modulo
  `usuarios`, no codigo dentro de cada controlador.
- Eliminar la cuenta borra tambien su consumo (evento `CuentaEliminada`).

## Consecuencias

El tope de prendas (30) y de dress code (3 al mes) del plan gratis **no salen del modelo
financiero**: son una propuesta a validar con el equipo, y basta con cambiarlos en
`CatalogoPlanes`.

Hoy solo el analisis de colorimetria gasta cuota, porque es la unica ruta del Core que
llama a la IA. El closet, los outfits y las funciones de Plus todavia no existen: cuando
existan, aplican sus topes con `PlanesUsuario.derechos()` y las rutas nuevas con IA se
agregan al interceptor.

Pendiente: cambiar el plan por una compra real. Va con Google Play Billing (comision del
15% en suscripciones segun el modelo) y la verificacion de la compra en el Core con la
Play Developer API. Necesita la cuenta de Play Console y una cuenta de servicio, que son
infraestructura. Hasta entonces el plan solo se cambia directo en la base.
