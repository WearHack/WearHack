package com.wearhack.usuarios.planes;

import static org.assertj.core.api.Assertions.assertThat;

import com.wearhack.usuarios.DerechosPlan;
import com.wearhack.usuarios.Plan;
import org.junit.jupiter.api.Test;

class CatalogoPlanesTest {

    @Test
    void sinPlanEsGratis() {
        assertThat(CatalogoPlanes.de(null).plan()).isEqualTo(Plan.GRATIS);
    }

    @Test
    void cadaPlanTieneSusDerechos() {
        for (Plan plan : Plan.values()) {
            assertThat(CatalogoPlanes.de(plan).plan()).isEqualTo(plan);
        }
    }

    @Test
    void elGratisLimitaPrendasYDressCode() {
        DerechosPlan gratis = CatalogoPlanes.de(Plan.GRATIS);

        assertThat(gratis.admitePrendaNueva(CatalogoPlanes.PRENDAS_PLAN_GRATIS - 1)).isTrue();
        assertThat(gratis.admitePrendaNueva(CatalogoPlanes.PRENDAS_PLAN_GRATIS)).isFalse();
        assertThat(gratis.admiteDressCode(CatalogoPlanes.DRESS_CODES_PLAN_GRATIS)).isFalse();
    }

    @Test
    void losDePagoNoLimitanPrendasNiDressCode() {
        for (Plan plan : new Plan[] {Plan.ESENCIAL, Plan.PLUS}) {
            DerechosPlan derechos = CatalogoPlanes.de(plan);
            assertThat(derechos.admitePrendaNueva(10_000)).isTrue();
            assertThat(derechos.admiteDressCode(10_000)).isTrue();
            assertThat(derechos.solicitudesIaPorMes()).isGreaterThan(CatalogoPlanes.de(Plan.GRATIS).solicitudesIaPorMes());
        }
    }

    @Test
    void soloPlusTieneLasFuncionesDePlus() {
        assertThat(CatalogoPlanes.de(Plan.PLUS).escaneoEnTienda()).isTrue();
        assertThat(CatalogoPlanes.de(Plan.ESENCIAL).escaneoEnTienda()).isFalse();
        assertThat(CatalogoPlanes.de(Plan.ESENCIAL).maleta()).isFalse();
        assertThat(CatalogoPlanes.de(Plan.GRATIS).analisisDelCloset()).isFalse();
    }
}
