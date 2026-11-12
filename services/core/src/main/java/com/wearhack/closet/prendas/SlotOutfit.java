package com.wearhack.closet.prendas;

/** Donde va la prenda en un outfit (respuestas C.18). Los nombres son los del esquema de Mongo. */
public enum SlotOutfit {
    TORSO_SUPERIOR,
    TORSO_INFERIOR,
    CUERPO_COMPLETO,
    CALZADO,
    EXTERIOR,
    ACCESORIO_CUELLO,
    ACCESORIO_RELOJ,
    ACCESORIO_CINTURA,
    ACCESORIO_CABEZA,
    ACCESORIO_BOLSO,
    ACCESORIO_OJOS,
    ACCESORIO_JOYERIA;

    /** El calzado y los accesorios no llevan textura: su clima sale del tipo. */
    public boolean llevaTextura() {
        return this == TORSO_SUPERIOR || this == TORSO_INFERIOR || this == CUERPO_COMPLETO || this == EXTERIOR;
    }
}
