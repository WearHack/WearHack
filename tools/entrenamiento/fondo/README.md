# Exportar u2netp (remocion de fondo, issue #12)

No se entrena nada: se exportan los pesos oficiales de U^2-Net a LiteRT. El plan
de reentrenar con mascaras de Fashionpedia u Open Images esta en
`docs/respuestas-claude-code.md`, punto 19.

## Pesos

`u2netp.pth` (4,7 MB, Apache 2.0) se baja a mano del enlace de Google Drive del
README de [xuebinqin/U-2-Net](https://github.com/xuebinqin/U-2-Net). No confundir
con `u2net.pth` ni `u2net_portrait.pth`, que pesan 176 MB.

La version usada:

```
SHA-256  e7567cde013fb64813973ce6e1ecc25a80c05c3ca7adbc5a54f3c3d90991b854
```

## Exportar

Corre en WSL con el mismo venv que el clasificador
(`../prendas/requirements-exportacion.txt`):

```bash
python tools/entrenamiento/fondo/exportar.py \
  --pesos /mnt/c/Users/<usuario>/Downloads/u2netp.pth \
  --salida ~/.wearhack/salidas/fondo
```

Deja `u2netp_fp32.tflite`, `u2netp_fp16.tflite` y `exportacion.json`. La app usa
la FP16, copiada como `client/assets/models/u2netp.tflite`.

`modelo_u2netp.py` reescribe la arquitectura con los nombres de capa del
original, asi que los pesos cargan con `strict=True`: si una capa no cuadra,
falla. Con la imagen sintetica del exportador la mascara da 0,997 dentro de la
prenda y 0,001 fuera; la FP16 se separa de PyTorch como maximo 0,02.
