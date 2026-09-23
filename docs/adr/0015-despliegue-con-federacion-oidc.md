# ADR 0015: Despliegue a ECS con federacion OIDC

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

GitHub Actions necesita credenciales de AWS para publicar en ECR y desplegar en
ECS. La alternativa clasica es guardar una clave de acceso como secreto.

## Decision

**Federacion OIDC, sin llaves estaticas.** GitHub pide un token y AWS lo cambia
por credenciales temporales.

Las imagenes se etiquetan con el SHA del commit ademas de `latest`. El despliegue
espera a que el servicio quede estable.

## Consecuencias

No hay nada que rotar ni que se pueda filtrar en un log. Las credenciales duran
lo que dura el job.

La politica de confianza del rol **tiene que acotar `sub` a este repositorio**.
Un rol que confie en toda la organizacion deja desplegar desde cualquier repo de
la cuenta, que es un agujero mas grande que el que veniamos a cerrar.

Etiquetar con el SHA hace que un rollback sea volver a desplegar un tag concreto
en vez de adivinar que habia antes en `latest`.

Esperar estabilidad alarga el workflow, pero sin eso sale en verde con las tareas
aun arrancando y un despliegue roto parece correcto.

Antes del primer despliegue hay que crear el proveedor OIDC y el rol. Hasta
entonces, los ARNs del workflow son placeholders.
