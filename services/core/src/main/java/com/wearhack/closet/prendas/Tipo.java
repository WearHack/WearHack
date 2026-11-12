package com.wearhack.closet.prendas;

/** El tipo de prenda y su slot por defecto (respuestas C.18). */
public enum Tipo {
    CAMISA(SlotOutfit.TORSO_SUPERIOR),
    CAMISETA(SlotOutfit.TORSO_SUPERIOR),
    SUETER(SlotOutfit.TORSO_SUPERIOR),
    CARDIGAN(SlotOutfit.EXTERIOR),
    CHAQUETA(SlotOutfit.EXTERIOR),
    ABRIGO(SlotOutfit.EXTERIOR),
    CHALECO(SlotOutfit.EXTERIOR),
    PANTALON(SlotOutfit.TORSO_INFERIOR),
    SHORT(SlotOutfit.TORSO_INFERIOR),
    FALDA(SlotOutfit.TORSO_INFERIOR),
    VESTIDO(SlotOutfit.CUERPO_COMPLETO),
    ENTERIZO(SlotOutfit.CUERPO_COMPLETO),
    CALZADO(SlotOutfit.CALZADO),
    GAFAS(SlotOutfit.ACCESORIO_OJOS),
    SOMBRERO(SlotOutfit.ACCESORIO_CABEZA),
    ACCESORIO_CABELLO(SlotOutfit.ACCESORIO_CABEZA),
    CORBATA(SlotOutfit.ACCESORIO_CUELLO),
    BUFANDA(SlotOutfit.ACCESORIO_CUELLO),
    RELOJ(SlotOutfit.ACCESORIO_RELOJ),
    CINTURON(SlotOutfit.ACCESORIO_CINTURA),
    BOLSO(SlotOutfit.ACCESORIO_BOLSO),
    JOYERIA(SlotOutfit.ACCESORIO_JOYERIA);

    private final SlotOutfit slot;

    Tipo(SlotOutfit slot) {
        this.slot = slot;
    }

    public SlotOutfit slot() {
        return slot;
    }
}
