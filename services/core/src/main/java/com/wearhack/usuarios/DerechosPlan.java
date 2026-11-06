package com.wearhack.usuarios;

/**
 * Lo que permite un plan. Los demas modulos lo consultan en vez de repetir la tabla.
 *
 * @param solicitudesIaPorMes solicitudes al servicio de IA que el usuario puede hacer en un
 *     mes calendario. No hay cobro por encima: al llegar al tope se responde 429
 * @param maxPrendas tope de prendas en el closet; {@code null} es ilimitado
 * @param dressCodesPorMes consultas de dress code al mes; {@code null} es ilimitado
 * @param escaneoEnTienda funcion de Plus
 * @param analisisDelCloset funcion de Plus
 * @param maleta funcion de Plus
 */
public record DerechosPlan(
        Plan plan,
        int solicitudesIaPorMes,
        Integer maxPrendas,
        Integer dressCodesPorMes,
        boolean escaneoEnTienda,
        boolean analisisDelCloset,
        boolean maleta) {

    /** Si con {@code prendasActuales} en el closet todavia cabe una mas. */
    public boolean admitePrendaNueva(long prendasActuales) {
        return maxPrendas == null || prendasActuales < maxPrendas;
    }

    /** Si con {@code usadosEsteMes} dress code todavia queda uno. */
    public boolean admiteDressCode(long usadosEsteMes) {
        return dressCodesPorMes == null || usadosEsteMes < dressCodesPorMes;
    }
}
