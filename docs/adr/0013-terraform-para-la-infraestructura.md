# ADR 0013: Terraform para la infraestructura

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

La infraestructura de AWS tiene que estar en codigo. Las opciones eran Terraform
o AWS CDK en TypeScript.

## Decision

**Terraform.** La carpeta `infra/terraform/` queda con la estructura de modulos
y sin recursos reales todavia.

## Consecuencias

HCL es declarativo y se lee sin saber el lenguaje, que baja la barrera para seis
generalistas que no van a tocar infra todos los dias. El `plan` dice exactamente
que va a cambiar.

CDK habria permitido escribir la infra en un lenguaje de programacion de verdad,
con abstracciones y tests, pero anade Node al toolchain de infra y una capa de
sintesis entre lo que escribes y lo que se aplica.

Terraform obliga a decidir donde vive el estado y como se bloquea antes del
primer `apply` compartido.

Mientras la carpeta siga vacia, lo que hay en AWS no esta en codigo. Ese hueco
es real y hay que cerrarlo antes del primer despliegue serio.
