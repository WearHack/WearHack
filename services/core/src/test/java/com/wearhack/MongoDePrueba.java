package com.wearhack;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.mongodb.MongoDBContainer;

/**
 * Un Mongo real en un contenedor, la misma version que el compose.
 *
 * <p>Las pruebas que lo importan llevan {@code @Testcontainers(disabledWithoutDocker = true)}:
 * sin Docker se saltan en vez de fallar. Las reglas de negocio tienen ademas pruebas
 * unitarias que no lo necesitan.
 */
@TestConfiguration(proxyBeanMethods = false)
public class MongoDePrueba {

    @Bean
    @ServiceConnection
    MongoDBContainer contenedorMongo() {
        return new MongoDBContainer("mongo:8.0");
    }
}
