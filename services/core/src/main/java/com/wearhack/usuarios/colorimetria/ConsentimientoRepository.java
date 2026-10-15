package com.wearhack.usuarios.colorimetria;

import java.util.List;
import java.util.Optional;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface ConsentimientoRepository extends MongoRepository<Consentimiento, String> {

    List<Consentimiento> findByUsuarioIdOrderByOtorgadoEnDesc(String usuarioId);

    Optional<Consentimiento> findFirstByUsuarioIdAndFinalidadAndEstado(
            String usuarioId, String finalidad, String estado);

    void deleteByUsuarioId(String usuarioId);
}
