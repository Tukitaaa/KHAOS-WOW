#!/usr/bin/env python3
"""Entrena el clasificador de intenciones de KHAOS (el "cerebro" que entiende qué preguntas).

1. Lee guias/intenciones.txt y genera miles de frases de ejemplo combinando las variantes.
2. Entrena un clasificador Naive Bayes sobre raíces de palabras y pares de palabras.
3. Mide el acierto con guias/intenciones_prueba.txt (frases escritas a mano que NO se usan
   para entrenar) y enseña los fallos.
4. Escribe KHAOS/Modelo.lua, que el addon usa dentro del juego.

Uso:  python3 herramientas/entrenar_intenciones.py
"""
import math
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texto_es  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
MAX_POR_PLANTILLA = 400
MAX_POR_INTENCION = 6000
ALFA = 0.3
random.seed(7)


# --------------------------------------------------------------------------- plantillas
def analizar(texto, i=0, cierre=None):
    """Convierte una plantilla en un árbol: lista de piezas (texto o lista de opciones)."""
    secuencia, opciones, actual = [], [], []
    while i < len(texto):
        c = texto[i]
        if c in "{[":
            sub, i = analizar(texto, i + 1, "}" if c == "{" else "]")
            if c == "[":
                sub = sub + [[]]  # opcional: también sin nada
            actual.append(sub)
            continue
        if cierre and c == cierre:
            opciones.append(actual)
            return opciones, i + 1
        if cierre and c == "|":
            opciones.append(actual)
            actual = []
        else:
            if actual and isinstance(actual[-1], str):
                actual[-1] += c
            else:
                actual.append(c)
        i += 1
    secuencia = actual
    return secuencia, i


def contar(sec):
    total = 1
    for p in sec:
        if isinstance(p, list):
            total *= sum(contar(o) for o in p)
    return total


def todas(sec):
    if not sec:
        yield ""
        return
    cabeza, resto = sec[0], sec[1:]
    if isinstance(cabeza, str):
        for r in todas(resto):
            yield cabeza + r
    else:
        for opcion in cabeza:
            for a in todas(opcion):
                for r in todas(resto):
                    yield a + r


def una(sec):
    out = []
    for p in sec:
        out.append(p if isinstance(p, str) else una(random.choice(p)))
    return "".join(out)


def expandir(plantilla):
    arbol, _ = analizar(plantilla)
    n = contar(arbol)
    if n <= MAX_POR_PLANTILLA:
        return list(todas(arbol))
    vistas = set()
    for _ in range(MAX_POR_PLANTILLA * 3):
        vistas.add(una(arbol))
        if len(vistas) >= MAX_POR_PLANTILLA:
            break
    return list(vistas)


def leer_corpus(ruta):
    macros, ejemplos, intencion = {}, defaultdict(list), None
    for linea in Path(ruta).read_text(encoding="utf-8").splitlines():
        linea = linea.rstrip()
        if linea.startswith("## "):
            intencion = linea[3:].strip()
            continue
        if not linea or linea.startswith("#"):
            continue
        if False:
            intencion = linea[3:].strip()
            continue
        m = re.match(r"^@(\w+)\s*=\s*(.*)$", linea)
        if m:
            macros[m.group(1)] = m.group(2)
            continue
        for nombre in sorted(macros, key=len, reverse=True):
            linea = linea.replace("@" + nombre, macros[nombre])
        if intencion:
            ejemplos[intencion].extend(" ".join(f.split()) for f in expandir(linea))
    return ejemplos


# --------------------------------------------------------------------------- modelo
class Modelo:
    def __init__(self, ejemplos):
        self.intenciones = sorted(ejemplos)
        cuentas = {c: Counter() for c in self.intenciones}
        for c, frases in ejemplos.items():
            frases = list(dict.fromkeys(frases))
            if len(frases) > MAX_POR_INTENCION:
                frases = random.sample(frases, MAX_POR_INTENCION)
            for f in frases:
                cuentas[c].update(set(texto_es.rasgos(f)))
        vocab = set()
        for c in cuentas.values():
            vocab |= set(c)
        V = len(vocab)
        self.defecto, self.peso = {}, defaultdict(dict)
        for i, c in enumerate(self.intenciones):
            total = sum(cuentas[c].values())
            den = total + ALFA * V
            self.defecto[i] = math.log(ALFA / den)
            for f, n in cuentas[c].items():
                self.peso[f][i] = math.log((n + ALFA) / den)
        self.prior = [math.log(1 / len(self.intenciones))] * len(self.intenciones)
        self.vocabulario = sorted({f for f in vocab if "_" not in f and not f.startswith("^")})
        self.ejemplos = {c: len(set(e)) for c, e in ejemplos.items()}

    def parecida(self, r):
        if len(r) < 5:
            return None
        for v in self.vocabulario:
            if len(v) >= 5 and abs(len(v) - len(r)) <= 1 and distancia(r, v, 1) <= 1:
                return v
        return None

    def clasificar(self, frase):
        raices = [texto_es.raiz(p) for p in texto_es.normalizar(frase)]
        raices = [r if (r in self.peso or r.startswith("x")) else (self.parecida(r) or r)
                  for r in raices]
        rasgos = list(raices) + [raices[i] + "_" + raices[i + 1] for i in range(len(raices) - 1)]
        rasgos.append("^" + (raices[0] if raices else ""))
        puntos = list(self.prior)
        for f in rasgos:
            w = self.peso.get(f)
            if w:
                for i in range(len(puntos)):
                    puntos[i] += w.get(i, self.defecto[i])
        m = max(puntos)
        exps = [math.exp(p - m) for p in puntos]
        s = sum(exps)
        mejor = max(range(len(puntos)), key=lambda i: puntos[i])
        return self.intenciones[mejor], exps[mejor] / s


def distancia(a, b, limite):
    if abs(len(a) - len(b)) > limite:
        return limite + 1
    previa = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        actual = [i]
        for j, cb in enumerate(b, 1):
            actual.append(min(previa[j] + 1, actual[j - 1] + 1, previa[j - 1] + (ca != cb)))
        if min(actual) > limite:
            return limite + 1
        previa = actual
    return previa[-1]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def exportar(modelo, ruta):
    L = ["-- ARCHIVO GENERADO por herramientas/entrenar_intenciones.py. No lo edites a mano:",
         "-- cambia guias/intenciones.txt y vuelve a entrenar.",
         "local _, ns = ...", "ns.Modelo = {"]
    L.append("intenciones = {" + ",".join(lua_str(c) for c in modelo.intenciones) + "},")
    L.append("prior = {" + ",".join("%.4f" % p for p in modelo.prior) + "},")
    L.append("defecto = {" + ",".join("%.4f" % modelo.defecto[i]
                                      for i in range(len(modelo.intenciones))) + "},")
    L.append("sufijos = {" + ",".join(lua_str(s) for s in texto_es.SUFIJOS) + "},")
    L.append("abreviaturas = {" + ",".join(f"[{lua_str(k)}]={lua_str(v)}"
                                          for k, v in sorted(texto_es.ABREVIATURAS.items())) + "},")
    L.append("vocabulario = {" + ",".join(lua_str(v) for v in modelo.vocabulario) + "},")
    L.append("peso = {")
    for f in sorted(modelo.peso):
        cuerpo = ",".join("[%d]=%.3f" % (i + 1, w) for i, w in sorted(modelo.peso[f].items()))
        L.append(f"[{lua_str(f)}]={{{cuerpo}}},")
    L.append("},")
    L.append("}")
    Path(ruta).write_text("\n".join(L) + "\n", encoding="utf-8")


def main():
    ejemplos = leer_corpus(RAIZ / "guias" / "intenciones.txt")
    modelo = Modelo(ejemplos)
    total = sum(modelo.ejemplos.values())
    print(f"Frases de entrenamiento: {total} en {len(modelo.intenciones)} tipos de pregunta")
    for c in modelo.intenciones:
        print(f"  {c:13s} {modelo.ejemplos[c]:6d}")

    prueba = []
    for linea in (RAIZ / "guias" / "intenciones_prueba.txt").read_text(encoding="utf-8").splitlines():
        if "|" in linea and not linea.startswith("#"):
            c, f = (s.strip() for s in linea.split("|", 1))
            prueba.append((c, f))
    fallos = []
    for c, f in prueba:
        pred, prob = modelo.clasificar(f)
        if pred != c:
            fallos.append((c, pred, prob, f))
    acierto = 100 * (len(prueba) - len(fallos)) / len(prueba)
    print(f"\nAcierto con {len(prueba)} preguntas nuevas (no vistas): {acierto:.1f}%")
    for c, pred, prob, f in fallos:
        print(f"  FALLO esperaba {c:12s} dijo {pred:12s} ({prob:.2f})  {f}")

    salida = RAIZ / "KHAOS" / "Modelo.lua"
    exportar(modelo, salida)
    print(f"\nOK: {salida.name} ({salida.stat().st_size // 1024} KB, {len(modelo.peso)} rasgos)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
