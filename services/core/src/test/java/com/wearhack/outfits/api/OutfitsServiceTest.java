package com.wearhack.outfits.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.wearhack.closet.PrendasParaOutfits;
import com.wearhack.closet.PrendasParaOutfits.Prenda;
import com.wearhack.closet.PrendasParaOutfits.Rango;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.usuarios.PlanesUsuario;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.stream.StreamSupport;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.web.server.ResponseStatusException;

class OutfitsServiceTest {
    private static final String ANA = "ana";
    private static final LocalDate HOY = LocalDate.parse("2026-11-24");
    private static final Instant AHORA = Instant.parse("2026-11-25T02:00:00Z");
    private static final OutfitsService.Contexto DIARIO =
            new OutfitsService.Contexto(OutfitsService.Ocasion.DIA_A_DIA, null, null);

    private final PrendasParaOutfits closet = mock(PrendasParaOutfits.class);
    private final ClienteRecomendador motor = mock(ClienteRecomendador.class);
    private final LotesOutfitsRepository lotes = mock(LotesOutfitsRepository.class);
    private final DiasOutfitsRepository dias = mock(DiasOutfitsRepository.class);
    private final PlanesUsuario planes = mock(PlanesUsuario.class);
    private final OutfitsService servicio = new OutfitsService(closet, motor, lotes, dias, planes,
            mock(MongoTemplate.class), Clock.fixed(AHORA, ZoneOffset.UTC));

    @BeforeEach
    void preparar() {
        var lotesGuardados = new HashMap<String, LoteOutfits>();
        var diasGuardados = new HashMap<String, DiaOutfit>();
        when(lotes.findById(anyString())).thenAnswer(i -> Optional.ofNullable(lotesGuardados.get(i.getArgument(0))));
        when(lotes.insert(any(LoteOutfits.class))).thenAnswer(i -> {
            LoteOutfits lote = i.getArgument(0);
            lotesGuardados.put(lote.id(), lote);
            return lote;
        });
        when(lotes.findByUsuarioAndFechaBetweenOrderByFechaDesc(anyString(), anyString(), anyString()))
                .thenAnswer(i -> lotesGuardados.values().stream()
                        .filter(lote -> lote.usuario().equals(i.getArgument(0))).toList());
        when(dias.findById(anyString())).thenAnswer(i -> Optional.ofNullable(diasGuardados.get(i.getArgument(0))));
        when(dias.findAllById(any())).thenAnswer(i -> {
            Iterable<String> ids = i.getArgument(0);
            return StreamSupport.stream(ids.spliterator(), false)
                    .filter(diasGuardados::containsKey).map(diasGuardados::get).toList();
        });
        when(dias.save(any(DiaOutfit.class))).thenAnswer(i -> {
            DiaOutfit dia = i.getArgument(0);
            diasGuardados.put(dia.id(), dia);
            return dia;
        });
    }

    @Test
    void closetIncompletoNoInvocaElMotorNiConsumeCuota() {
        when(closet.listar(ANA)).thenReturn(List.of(prenda("camisa", "TORSO_SUPERIOR")));
        assertThat(servicio.opcionesHoy(ANA, DIARIO).opciones()).isEmpty();
        assertThat(servicio.plan(ANA)).hasSize(7).allMatch(dia -> dia.outfit() == null);
        verifyNoInteractions(planes, motor);
    }

    @Test
    void eleccionPersisteEnElPlanYLaMismaPeticionNoConsumeDosCuotas() {
        recomendarDosCombinaciones();
        var hoy = servicio.opcionesHoy(ANA, DIARIO);
        var primera = hoy.opciones().getFirst();
        assertThat(hoy.fecha()).isEqualTo(HOY.toString());
        assertThat(servicio.opcionesHoy(ANA, DIARIO)).isEqualTo(hoy);
        verify(planes, times(1)).consumirSolicitudIa(ANA);

        servicio.elegir(ANA, hoy.id(), primera.id());
        servicio.elegir(ANA, hoy.id(), primera.id());
        assertThatThrownBy(() -> servicio.elegir(ANA, hoy.id(), hoy.opciones().getLast().id()))
                .isInstanceOf(ResponseStatusException.class);
        assertThat(servicio.plan(ANA).get(1).outfit()).isEqualTo(primera);
        assertThat(servicio.opcionesHoy(ANA, DIARIO).elegido()).isEqualTo(primera);

        servicio.asignar(ANA, HOY.plusDays(1), primera.id());
        servicio.asignar(ANA, HOY, null);
        assertThat(servicio.plan(ANA).get(1).outfit()).isNull();
        assertThat(servicio.plan(ANA).get(2).outfit()).isEqualTo(primera);
    }

    @Test
    void unaPrendaBorradaInvalidaElOutfitYNoSePuedeAsignarALaCuentaAjena() {
        recomendarDosCombinaciones();
        var hoy = servicio.opcionesHoy(ANA, DIARIO);
        String outfit = hoy.opciones().getFirst().id();
        servicio.elegir(ANA, hoy.id(), outfit);
        assertThatThrownBy(() -> servicio.elegir("otra", hoy.id(), outfit))
                .isInstanceOf(ReglaDeNegocioException.class);

        when(closet.listar(ANA)).thenReturn(List.of());
        assertThat(servicio.plan(ANA).get(1).outfit()).isNull();
        assertThatThrownBy(() -> servicio.asignar(ANA, HOY, outfit))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    private void recomendarDosCombinaciones() {
        var prendas = List.of(prenda("camisa", "TORSO_SUPERIOR"), prenda("pantalon", "TORSO_INFERIOR"),
                prenda("zapato", "CALZADO"), prenda("vestido", "CUERPO_COMPLETO"));
        when(closet.listar(ANA)).thenReturn(prendas);
        when(motor.generar(eq(ANA), eq("DIA_A_DIA"), eq(null), eq(null), any(), eq(prendas)))
                .thenReturn(List.of(new ClienteRecomendador.Combinacion(List.of("camisa", "pantalon", "zapato"), 0.1),
                        new ClienteRecomendador.Combinacion(List.of("vestido", "zapato"), 0.2)));
    }

    private static Prenda prenda(String id, String slot) {
        return new Prenda(id, slot, List.of(50.0, 0.0, 0.0), "TIPO", null, "LISO",
                new Rango("CASUAL", "CASUAL"), List.of("TEMPLADO"), 1, AHORA);
    }
}
