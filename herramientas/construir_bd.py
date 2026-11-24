#!/usr/bin/env python3
"""Convierte las guías de texto (carpeta guias/) en la base de datos Lua del addon.

Este es el paso de "entrenamiento": lee todas las guías, las normaliza
(minúsculas, sin tildes), extrae las palabras importantes y genera
KHAOS/Datos.lua, que el addon carga dentro del juego.

Uso:
    python3 herramientas/construir_bd.py
    python3 herramientas/construir_bd.py --guias otra_carpeta --salida ruta/Datos.lua
    python3 herramientas/construir_bd.py --pendientes "C:/.../WTF/Account/TUCUENTA/SavedVariables/KHAOS.lua"
        (lista las preguntas que el addon no supo responder, de más a menos repetidas)
"""
import argparse
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Palabras que no ayudan a buscar.
VACIAS = set("""
a al algo como con de del el en es esta este esto hay la las le lo los mas me mi
no o para pero por que se si sin su sus te tu un una uno y ya hacer hago puedo
donde cual cuando mision misiones quest the of to and in for is how do i
""".split())


def normalizar(texto):
    texto = unicodedata.normalize("NFD", texto.lower())
    texto = "".join(c for c in texto if unicodedata.category(c) != "Mn")
    return texto


def palabras(texto):
    return [p for p in re.findall(r"[a-z0-9']+", normalizar(texto))
            if len(p) > 2 and p not in VACIAS]


def leer_guias(carpeta):
    entradas = []
    for archivo in sorted(Path(carpeta).glob("*.txt")):
        actual = None
        en_texto = False
        for n, linea in enumerate(archivo.read_text(encoding="utf-8").splitlines(), 1):
            if linea.startswith("### id:"):
                actual = {"id": linea.split(":", 1)[1].strip(), "titulo": "",
                          "claves": [], "misiones": [], "ids": [], "texto": [],
                          "origen": f"{archivo.name}:{n}"}
                entradas.append(actual)
                en_texto = False
                continue
            if actual is None or (linea.startswith("#") and not en_texto):
                continue
            if en_texto:
                actual["texto"].append(linea.rstrip())
            elif linea.strip() == "---":
                en_texto = True
            elif ":" in linea:
                campo, valor = (s.strip() for s in linea.split(":", 1))
                if campo == "titulo":
                    actual["titulo"] = valor
                elif campo == "claves":
                    actual["claves"] = [c.strip() for c in valor.split(",") if c.strip()]
                elif campo == "ids":
                    actual["ids"] = [int(x) for x in re.findall(r"\d+", valor)]
                elif campo == "misiones":
                    actual["misiones"] = [m.strip() for m in valor.split("|") if m.strip()]
    return entradas


def validar(entradas):
    errores, vistos = [], set()
    for e in entradas:
        if e["id"] in vistos:
            errores.append(f"{e['origen']}: id repetido '{e['id']}'")
        vistos.add(e["id"])
        if not e["titulo"]:
            errores.append(f"{e['origen']}: falta 'titulo'")
        if not any(l.strip() for l in e["texto"]):
            errores.append(f"{e['origen']}: la guía no tiene texto")
    return errores


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def generar_lua(entradas):
    out = ["-- ARCHIVO GENERADO por herramientas/construir_bd.py. No lo edites a mano:",
           "-- cambia las guías en la carpeta guias/ y vuelve a ejecutar el script.",
           "local _, ns = ...", "ns.Guias = {"]
    for e in entradas:
        texto = "\n".join(e["texto"]).strip()
        # Peso de cada palabra: claves y título valen más que el texto.
        pesos = Counter()
        for p in palabras(" ".join(e["claves"])):
            pesos[p] += 5
        for p in palabras(e["titulo"]):
            pesos[p] += 3
        for p in palabras(" ".join(e["misiones"])):
            pesos[p] += 3
        for p in palabras(texto):
            pesos[p] += 1
        indice = ", ".join(f"[{lua_str(p)}]={w}" for p, w in sorted(pesos.items()))
        misiones = ", ".join(lua_str(normalizar(m)) for m in e["misiones"])
        claves = ", ".join(lua_str(normalizar(c)) for c in e["claves"])
        ids = ", ".join(f"[{i}]=true" for i in e["ids"])
        out += ["  {",
                f"    id = {lua_str(e['id'])},",
                f"    titulo = {lua_str(e['titulo'])},",
                f"    texto = {lua_str(texto)},",
                f"    claves = {{ {claves} }},",
                f"    misiones = {{ {misiones} }},",
                f"    questIDs = {{ {ids} }},",
                f"    indice = {{ {indice} }},",
                "  },"]
    out.append("}")
    return "\n".join(out) + "\n"


def mostrar_pendientes(ruta):
    texto = Path(ruta).read_text(encoding="utf-8", errors="replace")
    bloque = re.search(r"sinRespuesta\"?\]?\s*=\s*\{(.*?)\n\s*\}", texto, re.S)
    pares = re.findall(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*(\d+)', bloque.group(1)) if bloque else []
    if not pares:
        print("No hay preguntas sin respuesta guardadas.")
        return 0
    print("Preguntas sin respuesta (veces | pregunta):")
    for pregunta, veces in sorted(pares, key=lambda x: -int(x[1])):
        print(f"  {int(veces):4d} | {pregunta}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--guias", default=RAIZ / "guias")
    ap.add_argument("--salida", default=RAIZ / "KHAOS" / "Datos.lua")
    ap.add_argument("--pendientes", help="SavedVariables/KHAOS.lua del juego")
    args = ap.parse_args()
    if args.pendientes:
        return mostrar_pendientes(args.pendientes)

    entradas = leer_guias(args.guias)
    errores = validar(entradas)
    if errores:
        print("Errores en las guías:\n  " + "\n  ".join(errores), file=sys.stderr)
        return 1
    Path(args.salida).write_text(generar_lua(entradas), encoding="utf-8")
    print(f"OK: {len(entradas)} guías escritas en {args.salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
