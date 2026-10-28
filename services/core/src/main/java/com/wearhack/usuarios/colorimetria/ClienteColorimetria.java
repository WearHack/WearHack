package com.wearhack.usuarios.colorimetria;

public interface ClienteColorimetria {

    /**
     * Envia el recorte a Colorimetria y devuelve lo derivado.
     *
     * @throws com.wearhack.plataforma.ServicioIaNoDisponibleException si no responde o responde mal
     */
    ResultadoColorimetria analizar(byte[] recortePng);
}