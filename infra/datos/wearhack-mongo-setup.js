// WearHack — Capa de datos: issues #41, #43, #42 (índice) y siembra de configuración.
//
// Uso (contra la Mongo local de Carlos o contra Atlas):
//   mongosh "<URI>" --file wearhack-mongo-setup.js
//
// Es idempotente: puede correrse varias veces. No borra datos ni pisa valores
// de `configuracion` que ya hayan sido editados.
//
// Fuentes: respuestas-claude-code.md (C.15, C.18, D.22-D.28, G.41),
//          WearHack_Protocolos_Puertos.md (sección 6), stack-tecnologico (sección 5).
//
// Marcas:  [DEFINIDO]  = viene de los documentos, usar tal cual.
//          [PROPUESTA] = lo propongo yo; hay que confirmarlo con Ivan/Carlos/Camilo.
//          [NO DEFINIDO] = los documentos dicen que no está decidido; no se inventa.

// [PROPUESTA] nombre de la base de datos. Para probar sin tocar la real:
//   $env:WH_DB="wearhack_test"   (PowerShell)
const d = db.getSiblingDB(process.env.WH_DB || "wearhack");

// ---------------------------------------------------------------- Enums [DEFINIDO: C.18, C.15]
const SLOT_OUTFIT = [
  "TORSO_SUPERIOR", "TORSO_INFERIOR", "CUERPO_COMPLETO", "CALZADO", "EXTERIOR",
  "ACCESORIO_CUELLO", "ACCESORIO_RELOJ", "ACCESORIO_CINTURA", "ACCESORIO_CABEZA",
  "ACCESORIO_BOLSO", "ACCESORIO_OJOS", "ACCESORIO_JOYERIA",
];
const TIPO = [
  "CAMISA", "CAMISETA", "SUETER",
  "CARDIGAN", "CHAQUETA", "ABRIGO", "CHALECO",
  "PANTALON", "SHORT", "FALDA",
  "VESTIDO", "ENTERIZO",
  "CALZADO",
  "GAFAS", "SOMBRERO", "ACCESORIO_CABELLO", "CORBATA", "BUFANDA", "RELOJ", "CINTURON", "BOLSO",
  "JOYERIA",
];
const SUBTIPO_CALZADO = ["TENIS", "ZAPATO_FORMAL", "BOTAS", "SANDALIAS", "TACONES"];
const PATRON = ["LISO", "RAYAS", "CUADROS", "PUNTOS", "FLORAL", "ANIMAL", "GEOMETRICO", "OTRO_ESTAMPADO"];
const TEXTURA = ["LISO_LIGERO", "DENIM", "PUNTO", "PANO", "CUERO", "SATIN", "LINO", "DEPORTIVO", "ACOLCHADO", "OTRA"];
const FORMALIDAD = ["DEPORTIVO", "CASUAL", "SMART_CASUAL", "FORMAL"]; // orden ordinal
const CLIMA = ["FRIO", "TEMPLADO", "CALIDO"];
const COLOR_CATEGORIA = [
  "NEGRO", "BLANCO", "GRIS", "BEIGE", "CAFE", "VINOTINTO", "ROJO", "ROSADO", "FUCSIA", "NARANJA",
  "AMARILLO", "MOSTAZA", "VERDE_OLIVA", "VERDE", "TURQUESA", "CELESTE", "AZUL", "AZUL_MARINO", "MORADO", "LILA",
];

// ---------------------------------------------------------------- Helper
// validationLevel "moderate": no rompe documentos viejos de pruebas al actualizarlos.
// Cambiar a "strict" cuando la base real esté limpia.
function upsertCollection(name, validator) {
  const opts = { validator, validationLevel: "moderate", validationAction: "error" };
  if (d.getCollectionNames().includes(name)) {
    d.runCommand({ collMod: name, ...opts });
  } else {
    d.createCollection(name, opts);
  }
  print("OK colección: " + name);
}

// ---------------------------------------------------------------- #41  prendas
// Dueño: módulo Clóset. Jobs batch: solo lectura (contrato declarado).
// Estructura: slot_outfit va en la raíz y clima_apto bajo `atributos`, porque así
// está definido el índice ESR (usuario_id + slot_outfit + atributos.clima_apto).
// [PROPUESTA] nombre de colección "prendas", `imagen_key`, `creado_en`, `actualizado_en`.
// Reglas que $jsonSchema NO puede validar (hacerlas en el código del módulo Clóset):
//   - formalidad.min <= formalidad.max en el orden de FORMALIDAD.
//   - subtipo_calzado solo si tipo == CALZADO.
//   - textura == null en calzado y accesorios.
//   - CUERPO_COMPLETO excluyente con TORSO_SUPERIOR/INFERIOR (regla de outfit, no de prenda).
upsertCollection("prendas", {
  $jsonSchema: {
    bsonType: "object",
    required: ["usuario_id", "slot_outfit", "atributos", "imagen_key", "version_esquema"],
    properties: {
      usuario_id: { bsonType: "string", description: "sub de Cognito" }, // [PROPUESTA] string
      slot_outfit: { enum: SLOT_OUTFIT },
      imagen_key: { bsonType: "string", description: "clave del objeto en S3 (imagen sin fondo)" },
      version_esquema: { bsonType: ["int", "long"], minimum: 1 },
      creado_en: { bsonType: "date" },
      actualizado_en: { bsonType: "date" },
      atributos: {
        bsonType: "object",
        required: ["tipo", "patron", "textura", "formalidad", "clima_apto", "color"],
        properties: {
          tipo: { enum: TIPO },
          subtipo_calzado: { enum: [...SUBTIPO_CALZADO, null] },
          patron: { enum: PATRON },
          textura: { enum: [...TEXTURA, null] },
          formalidad: {
            // rango {min,max}; null en accesorios neutros (no entran al filtro)
            bsonType: ["object", "null"],
            required: ["min", "max"],
            properties: { min: { enum: FORMALIDAD }, max: { enum: FORMALIDAD } },
          },
          clima_apto: {
            bsonType: "array",
            minItems: 1,
            uniqueItems: true,
            items: { enum: CLIMA },
          },
          color: {
            // Lab es la fuente de verdad; la categoría es derivada (solo UI y filtros)
            bsonType: "object",
            required: ["lab", "categoria"],
            properties: {
              lab: { bsonType: "array", minItems: 3, maxItems: 3, items: { bsonType: "number" } },
              categoria: { enum: COLOR_CATEGORIA },
            },
          },
        },
      },
    },
  },
});

// ---------------------------------------------------------------- #42  índice ESR [DEFINIDO]
d.prendas.createIndex(
  { usuario_id: 1, slot_outfit: 1, "atributos.clima_apto": 1 },
  { name: "esr_usuario_slot_clima" }
);

// ---------------------------------------------------------------- #43  correcciones_clasificacion
// Dueño: módulo Clóset. "Lab + categoría confirmada, sin imagen".
// [NO DEFINIDO] si guarda usuario_id; aquí NO se guarda (menos datos personales).
// [NO DEFINIDO] dónde van las correcciones de tipo/patrón/textura (#55); falta decidirlo.
upsertCollection("correcciones_clasificacion", {
  $jsonSchema: {
    bsonType: "object",
    required: ["lab", "categoria_confirmada"],
    properties: {
      lab: { bsonType: "array", minItems: 3, maxItems: 3, items: { bsonType: "number" } },
      categoria_confirmada: { enum: COLOR_CATEGORIA },
      creado_en: { bsonType: "date" },
    },
  },
});

// ---------------------------------------------------------------- #43  configuracion
// Una colección, un documento por dueño. _id = nombre del dueño.
// Cada componente lee y escribe SOLO su documento (a nivel de aplicación).
upsertCollection("configuracion", {
  $jsonSchema: {
    bsonType: "object",
    required: ["_id"],
    properties: { _id: { enum: ["outfits", "colorimetria", "closet", "recomendacion"] } },
  },
});

// Marcador para valores que los documentos dejan sin definir: no se inventan.
const NO_DEFINIDO = { definido: false, valor: null };

const seeds = [
  {
    _id: "outfits", // D.24 [DEFINIDO]; topes de slots: C.18 [DEFINIDO]
    dress_codes: {
      DEPORTE: { min: "DEPORTIVO", max: "DEPORTIVO" },
      DIA_A_DIA: { min: "DEPORTIVO", max: "SMART_CASUAL" },
      SALIDA_CASUAL: { min: "CASUAL", max: "SMART_CASUAL" },
      OFICINA: { min: "SMART_CASUAL", max: "FORMAL" },
      ENTREVISTA: { min: "SMART_CASUAL", max: "FORMAL" },
      CENA_ELEGANTE: { min: "SMART_CASUAL", max: "FORMAL" },
      FORMAL: { min: "FORMAL", max: "FORMAL" },
    },
    tope_slots: { ACCESORIO_JOYERIA: 3 }, // por defecto 3, configurable
  },
  {
    _id: "recomendacion", // D.22-D.28, C.18 [DEFINIDO]
    bandas_clima_c: { frio_menor_que: 14, calido_mayor_que: 22 }, // TEMPLADO = 14-22
    pesos_iniciales: { color: 0.35, paleta: 0.25, formalidad: 0.25, textura: 0.15 },
    w_mood: 0.2,
    w_estacion: 0.1, // apagada en Colombia (|latitud| <= 23.5)
    n_outfits: 3,
    n_candidatas: 10,
    min_prendas_diferentes_entre_outfits: 2, // D.27
    aprendizaje: { min_selecciones_nuevas: 10, eta: 0.05, peso_min: 0.05, peso_max: 0.6, suavizado_coocurrencia: 5 },
    prenda_puente: { umbral_combinaciones_buenas: 5 },
    matiz: { analoga_delta_max: 30, triadica: { centro: 120, tol: 15 }, complementaria: { centro: 180, tol: 20 } },
    neutros: { croma_max: 15, oscuro: { l_max: 35, croma_max: 30 }, texturas_neutras: ["DENIM"] }, // D.23
    // [NO DEFINIDO] curva de croma y corte cálido/frío de matices:
    curva_croma: NO_DEFINIDO,
    corte_calido_frio: NO_DEFINIDO,
  },
  {
    _id: "colorimetria", // [NO DEFINIDO] A.7, A.8: van aquí, no en el código
    pixeles_minimos_por_region: NO_DEFINIDO,
    margen_borde_landmark: NO_DEFINIDO,
    percentiles_recorte: NO_DEFINIDO,
    umbral_baja_confianza: NO_DEFINIDO, // A.6 lo declara no definido; G.41 no lo lista aquí [PROPUESTA: ponerlo en este documento]
  },
  {
    _id: "closet", // [NO DEFINIDO] C.16
    umbral_baja_confianza_clasificador: NO_DEFINIDO,
  },
];

// $setOnInsert: crea el documento solo si no existe; nunca pisa ediciones posteriores.
seeds.forEach((s) => {
  const { _id, ...resto } = s;
  d.configuracion.updateOne({ _id }, { $setOnInsert: resto }, { upsert: true });
});
print("OK configuracion sembrada (4 documentos)");

// #43: "los valores no definidos van con marcador y se avisa; no se inventan".
function pendientes(obj, ruta) {
  let r = [];
  for (const [k, v] of Object.entries(obj)) {
    const p = ruta + "." + k;
    if (v && typeof v === "object" && !Array.isArray(v)) {
      if (v.definido === false) r.push(p);
      else r = r.concat(pendientes(v, p));
    }
  }
  return r;
}
const pend = [];
d.configuracion.find().forEach((doc) => pendientes(doc, doc._id).forEach((x) => pend.push(x)));
if (pend.length > 0) {
  print("AVISO: " + pend.length + " valor(es) NO DEFINIDO(S) en la documentación (no se inventaron):");
  pend.forEach((x) => print("  - configuracion." + x));
}
