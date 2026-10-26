package com.wearhack.usuarios.colorimetria;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface CorreccionColorimetriaRepository
        extends MongoRepository<CorreccionColorimetria, String> {

    /** Solo alcanza a las vinculadas: las desvinculadas ya no llevan {@code usuario_id}. */
    void deleteByUsuarioId(String usuarioId);
}
