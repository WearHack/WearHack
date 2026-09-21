/*
 * Colecciones base de WearHack.
 *
 * Lo ejecuta el contenedor de Mongo la primera vez que arranca con un volumen
 * vacio. Es idempotente, asi que tambien se puede lanzar a mano contra una base
 * existente:
 *
 *   docker compose exec -T mongo mongosh --quiet \
 *     "$MONGO_URI" < infra/local/mongo/init/01-colecciones.js
 *
 * El modelo es documental de verdad, no relacional disfrazado: una prenda es un
 * documento con sus atributos embebidos. No hay una coleccion de atributos ni
 * joins para leer un closet.
 */

const nombreBase = process.env.MONGO_DB || "wearhack";
const base = db.getSiblingDB(nombreBase);

// ---------------------------------------------------------------- vocabulario ---
// Los enums viven aqui y en el cliente Flutter. Si cambian, cambian en los dos
// sitios: el modelo on-device produce estos valores y la base los valida.
const TIPOS = [
  "camiseta", "camisa", "blusa", "sueter", "chaqueta", "abrigo",
  "pantalon", "jean", "falda", "short", "vestido",
  "zapato", "bota", "tenis", "sandalia", "accesorio",
];

const TEXTURAS = [
  "lisa", "punto", "denim", "cuero", "lana", "lino", "seda", "algodon", "sintetico",
];

const PATRONES = [
  "solido", "rayas", "cuadros", "floral", "lunares", "animal", "geometrico", "estampado",
];

const FORMALIDADES = ["deportivo", "casual", "smart_casual", "formal"];

// Un outfit se arma llenando slots. Un slot vacio es un hueco, no un error.
const SLOTS_OUTFIT = [
  "superior", "inferior", "cuerpo_entero", "exterior", "calzado", "accesorio",
];

const CLIMAS = ["frio", "templado", "calido", "lluvia"];

const CATEGORIAS_COLOR = [
  "blanco", "negro", "gris", "beige", "marron",
  "rojo", "naranja", "amarillo", "verde", "azul", "morado", "rosa",
  "multicolor",
];

// ------------------------------------------------------------ esquema prendas ---
// Minimo a proposito: solo lo que el pipeline on-device produce hoy y el
// recomendador necesita para filtrar. Validar de mas ahora obligaria a migrar
// documentos cada vez que el modelo aprenda un atributo nuevo.
const esquemaPrenda = {
  $jsonSchema: {
    bsonType: "object",
    title: "prenda",
    required: ["usuario_id", "tipo", "slot_outfit", "color", "atributos"],
    additionalProperties: true,
    properties: {
      usuario_id: { bsonType: "string" },
      tipo: { enum: TIPOS },
      slot_outfit: { enum: SLOTS_OUTFIT },

      color: {
        bsonType: "object",
        // Lab y no RGB: en Lab la distancia entre dos colores se parece a la
        // diferencia que percibe el ojo, que es justo lo que necesita la
        // colorimetria por nearest-centroid.
        required: ["lab", "categoria"],
        properties: {
          lab: {
            bsonType: "object",
            required: ["l", "a", "b"],
            properties: {
              l: { bsonType: "double", minimum: 0, maximum: 100 },
              a: { bsonType: "double", minimum: -128, maximum: 127 },
              b: { bsonType: "double", minimum: -128, maximum: 127 },
            },
          },
          // Redundante con lab a proposito: permite filtrar y agrupar sin
          // recalcular distancias en cada consulta.
          categoria: { enum: CATEGORIAS_COLOR },
        },
      },

      atributos: {
        bsonType: "object",
        required: ["textura", "patron", "formalidad", "clima_apto"],
        properties: {
          textura: { enum: TEXTURAS },
          patron: { enum: PATRONES },
          formalidad: { enum: FORMALIDADES },
          clima_apto: {
            bsonType: "array",
            minItems: 1,
            uniqueItems: true,
            items: { enum: CLIMAS },
          },
        },
      },
    },
  },
};

// ------------------------------------------------------------------ creacion ---
const existentes = new Set(base.getCollectionNames());

function crear(nombre, opciones) {
  if (existentes.has(nombre)) {
    print(`  = ${nombre} (ya existia)`);
    return;
  }
  base.createCollection(nombre, opciones || {});
  print(`  + ${nombre}`);
}

print(`Preparando la base '${nombreBase}'`);

crear("usuarios");
crear("prendas", {
  validator: esquemaPrenda,
  validationLevel: "strict",
  validationAction: "error",
});
crear("outfits");
crear("selecciones");
crear("correcciones_clasificacion");
crear("configuracion");
crear("catalogos");

// Si prendas ya existia, el validador puede estar desactualizado.
if (existentes.has("prendas")) {
  base.runCommand({
    collMod: "prendas",
    validator: esquemaPrenda,
    validationLevel: "strict",
    validationAction: "error",
  });
  print("  ~ validador de prendas actualizado");
}

// ------------------------------------------------------------------- indices ---
// Regla ESR: primero las igualdades, luego el criterio de orden, y al final el
// rango. La consulta caliente es "dame las prendas de este usuario que sirven
// para este slot y este clima", que es la que arma cada outfit.
//
//   usuario_id            igualdad, y lo mas selectivo: parte el indice por closet
//   slot_outfit           igualdad, y tambien el orden en que se arma el outfit
//   atributos.clima_apto  al final, porque se consulta con $in sobre un array
//
// clima_apto va ultimo tambien por otra razon: es multikey. Un campo array
// multiplica las entradas del indice, y ponerlo antes inflaria las ramas que
// hay que recorrer para cada usuario.
base.prendas.createIndex(
  { usuario_id: 1, slot_outfit: 1, "atributos.clima_apto": 1 },
  { name: "prendas_usuario_slot_clima" }
);
print("  + indice prendas_usuario_slot_clima");

print("Listo.");
