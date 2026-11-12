package com.wearhack.closet.prendas;

import java.util.List;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface PrendaRepository extends MongoRepository<Prenda, String> {

    /** Usa el prefijo del indice ESR: es la consulta del closet, con meta de 2 s. */
    List<Prenda> findByUsuarioIdOrderByCreadoEnDesc(String usuarioId);

    void deleteByUsuarioId(String usuarioId);
}
