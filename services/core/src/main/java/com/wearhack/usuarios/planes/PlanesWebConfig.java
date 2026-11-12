package com.wearhack.usuarios.planes;

import com.wearhack.usuarios.PlanesUsuario;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** Las rutas del Core que gastan cuota de IA. Una ruta nueva que llame a la IA va aqui. */
@Configuration
class PlanesWebConfig implements WebMvcConfigurer {

    static final String[] RUTAS_CON_IA = {"/api/v1/usuarios/me/colorimetria"};

    private final PlanesUsuario planes;

    PlanesWebConfig(PlanesUsuario planes) {
        this.planes = planes;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registro) {
        registro.addInterceptor(new CuotaIaInterceptor(planes)).addPathPatterns(RUTAS_CON_IA);
    }
}
