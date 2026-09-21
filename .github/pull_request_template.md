## Que cambia

<!-- Una o dos frases. Que hace este PR y por que. -->

## Servicios tocados

<!-- Marca los que aplican. Ayuda a saber que va a construir CI. -->

- [ ] client (Flutter)
- [ ] gateway
- [ ] usuarios
- [ ] closet
- [ ] outfits
- [ ] publicidad
- [ ] colorimetria
- [ ] recomendador
- [ ] infra / docker-compose
- [ ] CI/CD
- [ ] docs

## Como lo verifico

<!-- Los comandos exactos que corriste, o los pasos para reproducirlo. -->

```bash

```

## Checklist

- [ ] El servicio arranca y responde `/health`
- [ ] Las trazas siguen llegando al collector
- [ ] Si cambie una decision de arquitectura, hay un ADR en `docs/adr/`
- [ ] No hay secretos ni credenciales en el diff
