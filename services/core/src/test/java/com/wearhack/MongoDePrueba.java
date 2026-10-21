package com.wearhack;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.mongodb.MongoDBContainer;

/**
 * Un Mongo real en un contenedor.
 *
 * <p>Las pruebas que lo importan llevan {@code @Testcontainers(disabledWithoutDocker = true)}:
 * sin Docker se saltan en vez de fallar. Las reglas de negocio tienen ademas pruebas
 * unitarias que no lo necesitan.
 */
@TestConfiguration(proxyBeanMethods = false)
public class MongoDePrueba {

    /**
     * 7.0 y no 8.0 como el compose. Los runners de GitHub usan kernels de Linux 6.19 o
     * mas nuevos, y en ellos mongod 8.0 y 8.3 se niegan a arrancar por una
     * incompatibilidad de su TCMalloc con rseq (SERVER-121912); se arregla con un kernel
     * 7.0.14 o posterior. 7.0 no trae ese TCMalloc. Lo que usa el Core (actualizaciones
     * con pipeline, $dateToString, indices parciales) existe igual en 7.0.
     *
     * <p>Ni 8.2, que arranca solo porque le falta la comprobacion, ni
     * GLIBC_TUNABLES=glibc.pthread.rseq=1, que la salta dejando el fallo latente.
     */
    private static final String IMAGEN = "mongo:7.0";

    @Bean
    @ServiceConnection
    MongoDBContainer contenedorMongo() {
        MongoDBContainer mongo = new MongoDBContainer(IMAGEN);
        // Se arranca aqui y no se deja a Spring: si mongod muere al arrancar, Testcontainers
        // no lo detecta y el error llega despues como "MongoDBContainer should be started
        // first", sin los logs que dicen por que.
        mongo.start();
        if (!mongo.isRunning()) {
            String logs = mongo.getLogs();
            mongo.stop();
            throw new IllegalStateException("mongod se detuvo al arrancar. Logs:\n" + logs);
        }
        return mongo;
    }
}
