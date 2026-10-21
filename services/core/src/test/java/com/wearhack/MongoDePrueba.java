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
        MongoDBContainer mongo = new MongoDBContainer("mongo:8.0");
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
