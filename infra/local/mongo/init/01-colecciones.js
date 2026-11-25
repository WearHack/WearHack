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

// El vocabulario C.18 se persiste con los enums del módulo closet del Core.
const TIPOS = [
  "CAMISA", "CAMISETA", "SUETER", "CARDIGAN", "CHAQUETA", "ABRIGO",
  "CHALECO", "PANTALON", "SHORT", "FALDA", "VESTIDO", "ENTERIZO", "CALZADO",
  "GAFAS", "SOMBRERO", "ACCESORIO_CABELLO", "CORBATA", "BUFANDA", "RELOJ",
  "CINTURON", "BOLSO", "JOYERIA",
];
const TEXTURAS = [
  "LISO_LIGERO", "DENIM", "PUNTO", "PANO", "CUERO", "SATIN", "LINO",
  "DEPORTIVO", "ACOLCHADO", "OTRA",
];
const PATRONES = [
  "LISO", "RAYAS", "CUADROS", "PUNTOS", "FLORAL", "ANIMAL", "GEOMETRICO",
  "OTRO_ESTAMPADO",
];
const FORMALIDADES = ["DEPORTIVO", "CASUAL", "SMART_CASUAL", "FORMAL"];
const SLOTS_OUTFIT = [
  "TORSO_SUPERIOR", "TORSO_INFERIOR", "CUERPO_COMPLETO", "CALZADO", "EXTERIOR",
  "ACCESORIO_CUELLO", "ACCESORIO_RELOJ", "ACCESORIO_CINTURA", "ACCESORIO_CABEZA",
  "ACCESORIO_BOLSO", "ACCESORIO_OJOS", "ACCESORIO_JOYERIA",
];
const CLIMAS = ["FRIO", "TEMPLADO", "CALIDO"];
const CATEGORIAS_COLOR = [
  "NEGRO", "BLANCO", "GRIS", "BEIGE", "CAFE", "VINOTINTO", "ROJO", "ROSADO",
  "FUCSIA", "NARANJA", "AMARILLO", "MOSTAZA", "VERDE_OLIVA", "VERDE", "TURQUESA",
  "CELESTE", "AZUL", "AZUL_MARINO", "MORADO", "LILA",
];

const esquemaPrenda = {
  $jsonSchema: {
    bsonType: "object",
    title: "prenda",
    required: ["usuario_id", "slot_outfit", "atributos"],
    properties: {
      usuario_id: { bsonType: "string" },
      slot_outfit: { enum: SLOTS_OUTFIT },
      atributos: {
        bsonType: "object",
        required: ["tipo", "patron", "clima_apto", "color"],
        properties: {
          tipo: { enum: TIPOS },
          subtipo_calzado: { enum: ["TENIS", "ZAPATO_FORMAL", "BOTAS", "SANDALIAS", "TACONES", null] },
          textura: { enum: [...TEXTURAS, null] },
          patron: { enum: PATRONES },
          formalidad: {
            bsonType: ["object", "null"],
            required: ["min", "max"],
            properties: {
              min: { enum: FORMALIDADES },
              max: { enum: FORMALIDADES },
            },
          },
          clima_apto: {
            bsonType: "array",
            minItems: 1,
            uniqueItems: true,
            items: { enum: CLIMAS },
          },
          color: {
            bsonType: "object",
            required: ["lab", "categoria"],
            properties: {
              lab: {
                bsonType: "array",
                minItems: 3,
                maxItems: 3,
                items: { bsonType: "double" },
              },
              categoria: { enum: CATEGORIAS_COLOR },
            },
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
base.outfits.createIndex({ usuario_id: 1, fecha: -1 }, { name: "outfits_usuario_fecha" });
base.selecciones.createIndex({ usuario_id: 1 }, { name: "selecciones_usuario" });
crear("correcciones_clasificacion");
crear("configuracion");
crear("catalogos");
// Modulo usuarios: colorimetria. Solo valores derivados; el recorte facial nunca se guarda.
crear("perfiles_colorimetria");
crear("consentimientos");
crear("correcciones_colorimetria");
// Del job de recalibracion de centroides. El Core solo la lee.
crear("recalibraciones");

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

// "El consentimiento vigente de este usuario para esta finalidad", en cada
// otorgamiento y cada revocacion. otorgado_en al final sirve al historial, que
// se lista del mas reciente al mas antiguo.
base.consentimientos.createIndex(
  { usuario_id: 1, finalidad: 1, estado: 1, otorgado_en: -1 },
  { name: "consentimientos_usuario_finalidad_estado" }
);
print("  + indice consentimientos_usuario_finalidad_estado");

// La desvinculacion diaria busca vinculadas con creada_en hasta un corte. Es
// parcial: una correccion desvinculada ya no tiene usuario_id y sale del indice,
// asi que el indice no crece con el historico agregado.
base.correcciones_colorimetria.createIndex(
  { creada_en: 1, usuario_id: 1 },
  {
    name: "correcciones_vinculadas_por_fecha",
    partialFilterExpression: { usuario_id: { $exists: true } },
  }
);
print("  + indice correcciones_vinculadas_por_fecha");

// Borrar las correcciones de un usuario al revocar o eliminar la cuenta.
base.correcciones_colorimetria.createIndex(
  { usuario_id: 1 },
  {
    name: "correcciones_por_usuario",
    partialFilterExpression: { usuario_id: { $exists: true } },
  }
);
print("  + indice correcciones_por_usuario");

print("Listo.");
