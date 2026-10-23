// Pruebas de wearhack-mongo-setup.js. Correr DESPUÉS del setup, sobre la misma base.
//   mongosh "<URI>" --file wearhack-mongo-test.js
// Usa WH_DB igual que el setup. Los documentos de prueba llevan _test:true y se borran al final.

const d = db.getSiblingDB(process.env.WH_DB || "wearhack");
let fallos = 0;
let total = 0;
const ESPERADAS = 18; // cuántas comprobaciones debe ejecutar este archivo

function pasa(m) { total++; print("PASS  " + m); }
function falla(m) { total++; fallos++; print("FAIL  " + m); }

function debeAceptar(nombre, fn) {
  try { fn(); pasa(nombre); }
  catch (e) { falla(nombre + "  -> " + e.message); }
}
function debeRechazar(nombre, fn) {
  try { fn(); falla(nombre + "  (debía rechazarse y se aceptó)"); }
  catch (e) { pasa(nombre + "  (rechazado)"); }
}

// Prenda válida de base; cada prueba la modifica
function prenda(cambios = {}, atributos = {}) {
  return {
    _test: true,
    usuario_id: "test-usuario",
    slot_outfit: "TORSO_SUPERIOR",
    imagen_key: "prendas/test/1.png",
    version_esquema: NumberInt(1), // entero; un decimal (1.5) debe rechazarse
    atributos: {
      tipo: "CAMISETA",
      patron: "LISO",
      textura: "LISO_LIGERO",
      formalidad: { min: "CASUAL", max: "CASUAL" },
      clima_apto: ["TEMPLADO", "CALIDO"],
      color: { lab: [52.1, 3.4, -8.0], categoria: "AZUL" },
      ...atributos,
    },
    ...cambios,
  };
}

print("--- prendas ---");
debeAceptar("prenda válida", () => d.prendas.insertOne(prenda()));
debeAceptar("accesorio neutro (formalidad null, textura null)", () =>
  d.prendas.insertOne(prenda({ slot_outfit: "ACCESORIO_RELOJ" }, { tipo: "RELOJ", formalidad: null, textura: null })));
debeAceptar("calzado con subtipo", () =>
  d.prendas.insertOne(prenda({ slot_outfit: "CALZADO" }, { tipo: "CALZADO", subtipo_calzado: "TENIS", textura: null })));
debeRechazar("tipo inexistente", () => d.prendas.insertOne(prenda({}, { tipo: "BUFANDAZ" })));
debeRechazar("slot_outfit inexistente", () => d.prendas.insertOne(prenda({ slot_outfit: "CABEZA" })));
debeRechazar("clima_apto vacío", () => d.prendas.insertOne(prenda({}, { clima_apto: [] })));
debeRechazar("clima_apto con valor inválido", () => d.prendas.insertOne(prenda({}, { clima_apto: ["LLUVIOSO"] })));
debeRechazar("lab con 2 valores", () => d.prendas.insertOne(prenda({}, { color: { lab: [52.1, 3.4], categoria: "AZUL" } })));
debeRechazar("categoría de color inexistente", () =>
  d.prendas.insertOne(prenda({}, { color: { lab: [52.1, 3.4, -8.0], categoria: "CELESTINO" } })));
debeRechazar("formalidad con nivel inválido", () =>
  d.prendas.insertOne(prenda({}, { formalidad: { min: "ELEGANTE", max: "FORMAL" } })));
debeRechazar("falta usuario_id", () => { const p = prenda(); delete p.usuario_id; d.prendas.insertOne(p); });
debeRechazar("version_esquema decimal (1.5)", () => d.prendas.insertOne(prenda({ version_esquema: 1.5 })));

print("--- índice ---");
const idx = d.prendas.getIndexes().map((i) => i.name);
if (idx.includes("esr_usuario_slot_clima")) pasa("índice ESR existe");
else falla("falta el índice esr_usuario_slot_clima");

print("--- correcciones_clasificacion ---");
debeAceptar("corrección válida", () =>
  d.correcciones_clasificacion.insertOne({ _test: true, lab: [30, 5, 5], categoria_confirmada: "CAFE" }));
debeRechazar("corrección con categoría inválida", () =>
  d.correcciones_clasificacion.insertOne({ _test: true, lab: [30, 5, 5], categoria_confirmada: "MARRON" }));

print("--- configuracion ---");
const ids = d.configuracion.find({ _test: { $ne: true } }).toArray().map((x) => x._id).sort();
const esperados = ["closet", "colorimetria", "outfits", "recomendacion"];
if (JSON.stringify(ids) === JSON.stringify(esperados)) pasa("existen los 4 documentos");
else falla("documentos encontrados: " + ids.join(", "));

const rec = d.configuracion.findOne({ _id: "recomendacion" });
const suma = rec ? Object.values(rec.pesos_iniciales).reduce((a, b) => a + b, 0) : 0;
if (Math.abs(suma - 1) < 1e-9) pasa("pesos_iniciales suman 1");
else falla("pesos_iniciales suman " + suma);

debeRechazar("documento de configuracion con _id desconocido", () =>
  d.configuracion.insertOne({ _id: "otro", _test: true }));

// Limpieza
d.prendas.deleteMany({ _test: true });
d.correcciones_clasificacion.deleteMany({ _test: true });

print("\nComprobaciones ejecutadas: " + total + " (" + (total - fallos) + " PASS, " + fallos + " FAIL)");
if (total !== ESPERADAS) {
  fallos++;
  print("FAIL  se esperaban " + ESPERADAS + " comprobaciones y se ejecutaron " + total);
}
print(fallos === 0 ? "\nTODO OK" : "\n" + fallos + " problema(s)");
quit(fallos === 0 ? 0 : 1);
