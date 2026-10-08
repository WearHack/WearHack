package com.wearhack.usuarios.api;

import com.wearhack.plataforma.Estado;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Placeholder del modulo usuarios. Cuando haya logica, este se queda y los reales se suman. */
@RestController
@RequestMapping("/api/v1/usuarios")
public class UsuariosHealthController {

    private final String version;

    public UsuariosHealthController(@Value("${wearhack.version:desconocida}") String version) {
        this.version = version;
    }

    @GetMapping("/health")
    public Estado health() {
        return Estado.arriba("usuarios", version);
    }
}
