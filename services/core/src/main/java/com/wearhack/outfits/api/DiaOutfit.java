package com.wearhack.outfits.api;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;
import org.springframework.data.mongodb.repository.MongoRepository;

@Document("selecciones")
record DiaOutfit(@Id String id, @Field("usuario_id") String usuario, String fecha, String loteElegido,
        String outfitElegido, String asignado, @Version Long version) {
    static DiaOutfit vacio(String usuario, String fecha) {
        return new DiaOutfit(usuario + "/" + fecha, usuario, fecha, null, null, null, null);
    }

    DiaOutfit conAsignacion(String outfit) {
        return new DiaOutfit(id, usuario, fecha, loteElegido, outfitElegido, outfit, version);
    }

    DiaOutfit conEleccion(String lote, String outfit) {
        return new DiaOutfit(id, usuario, fecha, lote, outfit, outfit, version);
    }
}

interface DiasOutfitsRepository extends MongoRepository<DiaOutfit, String> {
    void deleteByUsuario(String usuario);
}
