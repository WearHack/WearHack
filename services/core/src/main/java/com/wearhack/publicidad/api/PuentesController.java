package com.wearhack.publicidad.api;

import com.wearhack.publicidad.puentes.RankingPrendaPuente;
import com.wearhack.publicidad.puentes.RankingPrendaPuenteRepository;
import java.time.Instant;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Las prendas puente del usuario del token, tal como las dejo el job. Si el job todavia no
 * ha corrido para el, la lista viene vacia: no es un error, es un usuario nuevo.
 */
@RestController
@RequestMapping("/api/v1/publicidad/me")
class PuentesController {

    private final RankingPrendaPuenteRepository rankings;

    PuentesController(RankingPrendaPuenteRepository rankings) {
        this.rankings = rankings;
    }

    @GetMapping("/puentes")
    PuentesRespuesta puentes(@AuthenticationPrincipal Jwt token) {
        return rankings.findById(token.getSubject())
                .map(PuentesRespuesta::de)
                .orElse(PuentesRespuesta.VACIA);
    }

    record PuentesRespuesta(List<RankingPrendaPuente.Puente> puentes, Instant calculadoEn) {

        static final PuentesRespuesta VACIA = new PuentesRespuesta(List.of(), null);

        static PuentesRespuesta de(RankingPrendaPuente ranking) {
            List<RankingPrendaPuente.Puente> puentes =
                    ranking.puentes() == null ? List.of() : ranking.puentes();
            return new PuentesRespuesta(puentes, ranking.calculadoEn());
        }
    }
}
