package com.wearhack.outfits.api;

import com.wearhack.plataforma.Estado;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Placeholder del modulo outfits. Cuando haya logica, este se queda y los reales se suman. */
@RestController
@RequestMapping("/api/v1/outfits")
public class OutfitsHealthController {

    private final String version;

    public OutfitsHealthController(@Value("${wearhack.version:desconocida}") String version) {
        this.version = version;
    }

    @GetMapping("/health")
    public Estado health() {
        return Estado.arriba("outfits", version);
    }
}
