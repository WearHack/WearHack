// WearHack — Verificación final de #41, #42, #43 y #59 sobre la base REAL.
//
// Uso (PowerShell, con las URIs de .env cargadas como variables de entorno):
//   mongosh.exe --nodb --file wearhack-mongo-verify.js
//
// Qué comprueba:
//   #41 / #43  validadores $jsonSchema presentes; configuracion con sus 4 documentos.
//   #42        índice ESR con la clave exacta.
//   #59        cada usuario de Atlas puede lo que debe y NO puede lo que no debe.
//
// Deja documentos { _test: true } solo mientras corre y los borra. Puede crear colecciones vacías
// (por ejemplo ranking_prenda_puente) al probar escrituras; no borra ninguna colección.
// Los nombres de colecciones marcados [PROPUESTA] en README.md deben coincidir con los reales.

const BASE = process.env.MONGODB_DB || "wearhack";
let fallos = 0;

const ok = (m) => print("PASS  " + m);
const mal = (m) => { fallos++; print("FAIL  " + m); };

function conectar(varEnv) {
  const uri = process.env[varEnv];
  if (!uri) { mal(varEnv + " no está definida"); return null; }
  try {
    const d = Mongo(uri).getDB(BASE);
    const quien = d.adminCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers.map((u) => u.user).join(", ");
    print("      conectado como: " + quien);
    return d;
  } catch (e) {
    mal("no se pudo conectar con " + varEnv + ": " + e.message);
    return null;
  }
}

function intentar(fn) {
  try { fn(); return { ok: true }; }
  catch (e) {
    const msg = String(e.message);
    // MongoDB responde "not authorized" (código 13); Atlas responde "user is not allowed to do action [...]"
    // (código 8000, AtlasError). Las dos significan "sin permiso".
    const sinPermiso = e.code === 13 || e.code === 8000 || /not authorized|unauthorized|not allowed to do action/i.test(msg);
    return { ok: false, noAutorizado: sinPermiso, msg };
  }
}

function debeLeer(d, c) {
  const r = intentar(() => d.getCollection(c).findOne());
  if (r.ok) ok("lee " + c); else mal("debía poder leer " + c + " -> " + r.msg);
}
function noDebeLeer(d, c) {
  const r = intentar(() => d.getCollection(c).findOne());
  if (r.ok) mal("NO debía poder leer " + c);
  else if (r.noAutorizado) ok("no lee " + c + " (bloqueado)");
  else mal("error inesperado al leer " + c + " -> " + r.msg);
}
function debeEscribir(d, c) {
  const col = d.getCollection(c);
  const r = intentar(() => { col.insertOne({ _test: true }); col.deleteMany({ _test: true }); });
  if (r.ok) ok("escribe " + c); else mal("debía poder escribir " + c + " -> " + r.msg);
}
// Colecciones con validador: un documento inválido falla con código 121 DESPUÉS de pasar la
// autorización. Por eso 121 prueba que el usuario SÍ tiene permiso de escritura, sin escribir datos.
function debeEscribirValidada(d, c) {
  const r = intentar(() => d.getCollection(c).insertOne({ _id: "__verificacion__", _test: true }));
  if (r.ok) { intentar(() => d.getCollection(c).deleteMany({ _test: true })); mal(c + " aceptó un documento inválido: falta el validador"); }
  else if (r.noAutorizado) mal("debía poder escribir " + c + " -> " + r.msg);
  else if (/validation/i.test(r.msg)) ok("escribe " + c + " (el validador rechazó el documento vacío, como debe)");
  else mal("error inesperado al escribir " + c + " -> " + r.msg);
}
function noDebeEscribir(d, c) {
  const col = d.getCollection(c);
  const r = intentar(() => col.insertOne({ _id: "__verificacion__", _test: true }));
  if (r.ok) { intentar(() => col.deleteMany({ _test: true })); mal("NO debía poder escribir " + c); }
  else if (r.noAutorizado) ok("no escribe " + c + " (bloqueado)");
  else mal("error inesperado al escribir " + c + " -> " + r.msg);
}

// Matriz de permisos: debe coincidir con README.md
const usuarios = {
  CORE: {
    env: "MONGODB_URI_CORE",
    escribe: ["usuarios", "consentimientos", "correcciones_colorimetria", "perfiles_colorimetria",
              "outfits", "selecciones", "catalogos_marcas", "centroides_color_prenda",
              "ajustes_categoria_color"],
    escribeValidadas: ["prendas", "correcciones_clasificacion", "configuracion"],
    lee: ["prendas", "correcciones_clasificacion", "configuracion", "recalibraciones", "ranking_prenda_puente"],
    noLee: ["centroides_temporada", "pesos_usuario", "coocurrencia_texturas"],
    noEscribe: ["recalibraciones", "ranking_prenda_puente", "centroides_temporada"],
  },
  COLORIMETRIA: {
    env: "MONGODB_URI_COLORIMETRIA",
    escribe: [],
    lee: ["centroides_temporada", "configuracion"],
    noLee: ["prendas", "usuarios", "consentimientos", "outfits", "pesos_usuario", "ranking_prenda_puente"],
    noEscribe: ["centroides_temporada", "configuracion"],
  },
  RECOMENDACION: {
    env: "MONGODB_URI_RECOMENDACION",
    escribe: [],
    lee: ["pesos_usuario", "coocurrencia_texturas", "configuracion"],
    noLee: ["prendas", "usuarios", "consentimientos", "centroides_temporada"],
    noEscribe: ["pesos_usuario", "coocurrencia_texturas", "configuracion"],
  },
  JOBS: {
    env: "MONGODB_URI_JOBS",
    escribe: ["centroides_temporada", "pesos_usuario", "coocurrencia_texturas", "recalibraciones", "ranking_prenda_puente"],
    lee: ["prendas", "correcciones_clasificacion", "correcciones_colorimetria", "outfits", "selecciones",
          "catalogos_marcas", "configuracion"],
    noLee: ["usuarios", "consentimientos", "perfiles_colorimetria", "centroides_color_prenda"],
    noEscribe: ["prendas", "correcciones_clasificacion", "outfits", "selecciones", "configuracion"],
  },
};

const conexiones = {};
for (const [nombre, cfg] of Object.entries(usuarios)) {
  print("\n--- #59 usuario " + nombre + " ---");
  const d = conectar(cfg.env);
  conexiones[nombre] = d;
  if (!d) continue;
  cfg.lee.forEach((c) => debeLeer(d, c));
  cfg.escribe.forEach((c) => debeEscribir(d, c));
  (cfg.escribeValidadas || []).forEach((c) => debeEscribirValidada(d, c));
  cfg.noLee.forEach((c) => noDebeLeer(d, c));
  cfg.noEscribe.forEach((c) => noDebeEscribir(d, c));
}

// ---------------------------------------------------------------- #41, #42, #43 (estado de la base)
print("\n--- #41 / #42 / #43 estado de la base (con el usuario CORE) ---");
const core = conexiones.CORE;
if (!core) {
  mal("sin conexión del Core; no se puede revisar el estado de la base");
} else {
  ["prendas", "correcciones_clasificacion", "configuracion"].forEach((c) => {
    const info = core.getCollectionInfos({ name: c })[0];
    if (info && info.options && info.options.validator && info.options.validator.$jsonSchema) ok("validador $jsonSchema en " + c);
    else mal("falta el validador $jsonSchema en " + c + " (¿corriste el setup sobre la base real?)");
  });

  const idx = core.prendas.getIndexes().find((i) => i.name === "esr_usuario_slot_clima");
  const claveEsperada = '{"usuario_id":1,"slot_outfit":1,"atributos.clima_apto":1}';
  if (idx && JSON.stringify(idx.key) === claveEsperada) ok("índice ESR con la clave esperada");
  else mal("índice ESR ausente o con otra clave: " + (idx ? JSON.stringify(idx.key) : "no existe"));

  const plan = JSON.stringify(
    core.prendas.find({ usuario_id: "x", slot_outfit: "TORSO_SUPERIOR", "atributos.clima_apto": "FRIO" }).explain("queryPlanner")
  );
  print("INFO  plan de la consulta típica: " + (plan.includes("IXSCAN") ? "IXSCAN (usa índice)" : "sin IXSCAN, revisar"));

  const ids = core.configuracion.find({}, { _id: 1 }).toArray().map((x) => x._id).sort();
  const esperados = ["closet", "colorimetria", "outfits", "recomendacion"];
  if (JSON.stringify(ids) === JSON.stringify(esperados)) ok("configuracion tiene los 4 documentos por dueño");
  else mal("configuracion tiene: " + ids.join(", "));
}

print(fallos === 0 ? "\nTODO OK" : "\n" + fallos + " comprobación(es) fallaron");
quit(fallos === 0 ? 0 : 1);
