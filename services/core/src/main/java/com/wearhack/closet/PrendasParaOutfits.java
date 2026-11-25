package com.wearhack.closet;

import com.wearhack.closet.prendas.PrendasService;
import java.time.Instant;
import java.util.List;
import org.springframework.stereotype.Component;

/** Consulta del clóset que usa el módulo Outfits. */
@Component
public class PrendasParaOutfits {
    private final PrendasService prendas;

    PrendasParaOutfits(PrendasService prendas) {
        this.prendas = prendas;
    }

    public record Rango(String min, String max) {}

    public record Prenda(String id, String slot, List<Double> lab, String tipo, String textura, String patron,
            Rango formalidad, List<String> climas, int version, Instant actualizada) {}

    public List<Prenda> listar(String usuario) {
        return prendas.listar(usuario).stream().map(p -> {
            var a = p.atributos();
            var formalidad = a.formalidad();
            return new Prenda(p.id(), p.slotOutfit().name(), a.color().lab(), a.tipo().name(),
                    a.textura() == null ? null : a.textura().name(), a.patron().name(),
                    formalidad == null ? null : new Rango(formalidad.min().name(), formalidad.max().name()),
                    a.climaApto().stream().map(Enum::name).toList(), p.versionEsquema(), p.actualizadoEn());
        }).toList();
    }
}
