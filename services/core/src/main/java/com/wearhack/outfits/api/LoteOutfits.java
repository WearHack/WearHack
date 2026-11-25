package com.wearhack.outfits.api;

import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;
import org.springframework.data.mongodb.repository.MongoRepository;

@Document("outfits")
record LoteOutfits(@Id String id, @Field("usuario_id") String usuario, String fecha, List<Opcion> opciones) {
    record Opcion(String id, List<String> prendas, String formalidad, String clima, double costo) {}
}

interface LotesOutfitsRepository extends MongoRepository<LoteOutfits, String> {
    List<LoteOutfits> findByUsuarioAndFechaBetweenOrderByFechaDesc(String usuario, String desde, String hasta);
    void deleteByUsuario(String usuario);
}
