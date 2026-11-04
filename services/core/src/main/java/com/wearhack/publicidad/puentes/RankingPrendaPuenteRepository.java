package com.wearhack.publicidad.puentes;

import java.util.Optional;
import org.springframework.data.repository.Repository;

/**
 * Solo lectura a proposito: extiende {@link Repository} y no {@code MongoRepository}, asi
 * que no hay {@code save} ni {@code delete} que llamar. La coleccion es del job; en Atlas
 * {@code wh_core} tampoco tiene permiso de escritura sobre ella.
 */
public interface RankingPrendaPuenteRepository extends Repository<RankingPrendaPuente, String> {

    Optional<RankingPrendaPuente> findById(String usuarioId);
}
