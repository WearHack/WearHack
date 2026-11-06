package com.wearhack.usuarios.perfil;

import com.wearhack.usuarios.Plan;
import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * El perfil de negocio de una persona.
 *
 * <p>No guarda correo ni credenciales: esos viven en Cognito. El {@code _id} es el
 * {@code sub} del token, asi que un perfil no se puede vincular a otra cuenta.
 *
 * @param id el {@code sub} de Cognito
 * @param nombre como quiere que la app la llame. Opcional
 * @param mayoriaEdadDeclaradaEn cuando marco la casilla de mayoria de edad. Es una
 *     declaracion, no una verificacion; se guarda como evidencia y no cambia despues
 * @param plan el nivel de suscripcion. {@code null} en los perfiles creados antes de que
 *     existieran los planes: cuenta como {@link Plan#GRATIS}
 */
@Document("usuarios")
public record Usuario(
        @Id String id,
        String nombre,
        @Field("mayoria_edad_declarada_en") Instant mayoriaEdadDeclaradaEn,
        @Field("creado_en") Instant creadoEn,
        @Field("actualizado_en") Instant actualizadoEn,
        Plan plan) {

    /** Un perfil nuevo: empieza en el plan gratis. */
    public Usuario(String id, String nombre, Instant mayoriaEdadDeclaradaEn, Instant creadoEn, Instant actualizadoEn) {
        this(id, nombre, mayoriaEdadDeclaradaEn, creadoEn, actualizadoEn, Plan.GRATIS);
    }

    public Plan planVigente() {
        return plan == null ? Plan.GRATIS : plan;
    }

    Usuario conNombre(String nuevoNombre, Instant ahora) {
        return new Usuario(id, nuevoNombre, mayoriaEdadDeclaradaEn, creadoEn, ahora, plan);
    }
}
