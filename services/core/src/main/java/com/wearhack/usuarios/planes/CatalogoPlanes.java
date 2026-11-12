package com.wearhack.usuarios.planes;

import com.wearhack.usuarios.DerechosPlan;
import com.wearhack.usuarios.Plan;
import java.util.Map;

/**
 * La tabla de derechos de cada plan.
 *
 * <p>Las solicitudes de IA salen del modelo financiero: unas 15 al mes en el plan gratis
 * (plan semanal 4, eventos 4, ranking 4, preferencias y colorimetria ~3) y 30 en los de
 * pago. El modelo no fija el tope de prendas ni de dress code del plan gratis: 30 y 3 son
 * una propuesta a validar con el equipo.
 */
final class CatalogoPlanes {

    static final int PRENDAS_PLAN_GRATIS = 30;
    static final int DRESS_CODES_PLAN_GRATIS = 3;

    private static final Map<Plan, DerechosPlan> DERECHOS = Map.of(
            Plan.GRATIS, new DerechosPlan(
                    Plan.GRATIS, 15, PRENDAS_PLAN_GRATIS, DRESS_CODES_PLAN_GRATIS, false, false, false),
            Plan.ESENCIAL, new DerechosPlan(Plan.ESENCIAL, 30, null, null, false, false, false),
            Plan.PLUS, new DerechosPlan(Plan.PLUS, 30, null, null, true, true, true));

    private CatalogoPlanes() {}

    static DerechosPlan de(Plan plan) {
        return DERECHOS.get(plan == null ? Plan.GRATIS : plan);
    }
}
