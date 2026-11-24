#!/usr/bin/env python3
"""Importa TODAS las misiones de Legion desde la base de datos libre de TrinityCore
(TDB 7.3.5, licencia GPL) y genera los archivos Misiones_*.lua del addon KHAOS.

Uso:
    python3 herramientas/importar_tdb.py RUTA/TDB_world_735.00_2018_02_19.sql

Genera KHAOS/Misiones_esES.lua, Misiones_esMX.lua y Misiones_enUS.lua. El addon
solo usa el del idioma de tu cliente (los otros se descartan al cargar).
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tdb_sql import leer_tablas, como_dicts  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
LEGION = 6
IDIOMAS = ["esES", "esMX", "enUS"]
TABLAS = ["quest_template", "quest_template_locale", "quest_objectives",
          "quest_objectives_locale", "quest_template_addon", "creature_queststarter",
          "creature_questender", "gameobject_queststarter", "gameobject_questender",
          "creature_template", "creature_template_locale", "gameobject_template",
          "gameobject_template_locale", "quest_poi", "quest_poi_points"]
DESCARTAR = re.compile(r"\b(DNT|UNUSED|PH|TEST|DEPRECATED|ZZOLD|OLD)\b|\[|^\s*$", re.I)

ALIANZA = 1 | 4 | 8 | 64 | 1024 | 2097152 | 8388608
HORDA = 2 | 16 | 32 | 128 | 256 | 512 | 16777216
WQ, SOLO_A, SOLO_H = 1, 2, 4


def limpiar(texto):
    texto = (texto or "").replace("\r", "")
    texto = re.sub(r"\$[bB]", "\n", texto)
    texto = re.sub(r"\n{3,}", "\n\n", texto)
    return texto.strip()


def lua_str(s):
    s = (s or "").replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + s.replace("|", "||") + '"'


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    print("Leyendo la base de datos (tarda ~30 s)...")
    d = {k: como_dicts(v) for k, v in leer_tablas(sys.argv[1], TABLAS).items()}

    misiones = {q["ID"]: q for q in d["quest_template"]
                if q["Expansion"] == LEGION and not DESCARTAR.search(q["LogTitle"] or "")}
    print(f"Misiones de Legion: {len(misiones)}")

    def por_idioma(filas, clave):
        out = defaultdict(dict)
        for r in filas:
            out[r["locale"]][r[clave]] = r
        return out

    q_loc = por_idioma(d["quest_template_locale"], "ID")
    obj_loc = por_idioma(d["quest_objectives_locale"], "ID")
    npc_loc = por_idioma(d["creature_template_locale"], "entry")
    go_loc = por_idioma(d["gameobject_template_locale"], "entry")
    npc_en = {r["entry"]: r["name"] for r in d["creature_template"]}
    go_en = {r["entry"]: r["name"] for r in d["gameobject_template"]}
    addon = {r["ID"]: r for r in d["quest_template_addon"]}

    objetivos = defaultdict(list)
    for o in d["quest_objectives"]:
        if o["QuestID"] in misiones:
            objetivos[o["QuestID"]].append(o)
    for lista in objetivos.values():
        lista.sort(key=lambda o: o["Order"])

    inicio, fin = defaultdict(list), defaultdict(list)
    for tabla, destino, tipo in [("creature_queststarter", inicio, "npc"),
                                 ("creature_questender", fin, "npc"),
                                 ("gameobject_queststarter", inicio, "go"),
                                 ("gameobject_questender", fin, "go")]:
        for r in d[tabla]:
            if r["quest"] in misiones and (tipo, r["id"]) not in destino[r["quest"]]:
                destino[r["quest"]].append((tipo, r["id"]))

    mapa = {}
    for p in sorted(d["quest_poi"], key=lambda p: (p["ObjectiveIndex"] != -1, p["Idx1"])):
        if p["QuestID"] in misiones and p["WorldMapAreaId"] and p["QuestID"] not in mapa:
            mapa[p["QuestID"]] = p["WorldMapAreaId"]

    # Misión previa y siguiente.
    previa, siguiente = {}, defaultdict(list)
    for qid in misiones:
        a = addon.get(qid) or {}
        prev = abs(a.get("PrevQuestID") or 0)
        if prev in misiones:
            previa[qid] = prev
            siguiente[prev].append(qid)
        nxt = a.get("NextQuestID") or misiones[qid]["RewardNextQuest"] or 0
        nxt = abs(nxt)
        if nxt in misiones and nxt not in previa:
            previa[nxt] = qid
            siguiente[qid].append(nxt)

    def nombre(tipo, ident, idioma):
        tabla, en = (npc_loc, npc_en) if tipo == "npc" else (go_loc, go_en)
        if idioma != "enUS":
            fila = tabla[idioma].get(ident)
            campo = "Name" if tipo == "npc" else "name"
            if fila and fila.get(campo):
                return fila[campo]
        return en.get(ident) or ""

    # Puntos del mapa (coordenadas del mundo; el addon las pasa a % del mapa al calibrar).
    puntos_blob = defaultdict(list)
    for r in d["quest_poi_points"]:
        if r["QuestID"] in misiones:
            puntos_blob[(r["QuestID"], r["Idx1"])].append((r["X"], r["Y"]))
    puntos = defaultdict(list)
    vistos = set()
    for p in sorted(d["quest_poi"], key=lambda p: (p["QuestID"], p["ObjectiveIndex"] == -1, p["Idx1"])):
        pts = puntos_blob.get((p["QuestID"], p["Idx1"]))
        if not pts or not p["WorldMapAreaId"]:
            continue
        tipo = 1 if p["ObjectiveIndex"] == -1 else 0
        clave = (p["QuestID"], p["WorldMapAreaId"], tipo)
        if clave in vistos or len(puntos[p["QuestID"]]) >= 4:
            continue
        vistos.add(clave)
        cx = round(sum(x for x, _ in pts) / len(pts))
        cy = round(sum(y for _, y in pts) / len(pts))
        puntos[p["QuestID"]].append((p["WorldMapAreaId"], tipo, cx, cy))
    lineas = ["-- ARCHIVO GENERADO por herramientas/importar_tdb.py (TrinityCore TDB 7.3.5, GPL).",
              "-- [questID] = { {mapa, tipo (0 objetivo, 1 entrega), X mundo (norte), Y mundo (oeste)}, ... }",
              "local _, ns = ...", "ns.Puntos = {"]
    for qid in sorted(puntos):
        cuerpo = ",".join("{%d,%d,%d,%d}" % t for t in puntos[qid])
        lineas.append(f"[{qid}]={{{cuerpo}}},")
    lineas.append("}")
    salida = RAIZ / "KHAOS" / "Puntos.lua"
    salida.write_text("\n".join(lineas) + "\n", encoding="utf-8")
    print(f"OK: Puntos.lua ({len(puntos)} misiones con puntos, {salida.stat().st_size // 1024} KB)")

    for idioma in IDIOMAS:
        lineas = [
            "-- ARCHIVO GENERADO por herramientas/importar_tdb.py a partir de TrinityCore TDB 7.3.5 (GPL).",
            f'if GetLocale and GetLocale() ~= "{idioma}" and not ("{idioma}" == "enUS") then return end',
            "local _, ns = ...",
            f'if ns.MisionesIdioma and "{idioma}" == "enUS" then return end',
            f'ns.MisionesIdioma = "{idioma}"',
            "-- {titulo, resumen, {objetivos}, empieza, entrega, previa, siguiente, mapa, nivel, banderas}",
            "ns.Misiones = {",
        ]
        for qid in sorted(misiones):
            q = misiones[qid]
            loc = q_loc[idioma].get(qid) if idioma != "enUS" else None
            titulo = (loc or {}).get("LogTitle") or q["LogTitle"]
            resumen = limpiar((loc or {}).get("LogDescription") or q["LogDescription"])
            cantidades = [o["Amount"] for o in objetivos.get(qid, [])]

            def cantidad(mt):
                n = int(mt.group(1) or 1) - 1
                return str(cantidades[n]) if 0 <= n < len(cantidades) else "varios"
            resumen = re.sub(r"\$(\d?)oa", cantidad, resumen)
            objs = []
            for o in objetivos.get(qid, []):
                ol = obj_loc[idioma].get(o["ID"]) if idioma != "enUS" else None
                texto = limpiar((ol or {}).get("Description") or o["Description"])
                if texto:
                    objs.append(texto)
            empieza = " / ".join(dict.fromkeys(filter(None, (nombre(t, i, idioma) for t, i in inicio[qid]))))
            entrega = " / ".join(dict.fromkeys(filter(None, (nombre(t, i, idioma) for t, i in fin[qid]))))
            if not empieza and previa.get(qid):
                # La base no dice quién la da: suele darla quien entrega la misión anterior.
                prev_fin = " / ".join(dict.fromkeys(filter(None, (nombre(t, i, idioma) for t, i in fin[previa[qid]]))))
                if prev_fin:
                    empieza = "~" + prev_fin
            banderas = WQ if q["QuestType"] == 3 else 0
            razas = q["AllowableRaces"] or 0
            if razas and razas != -1:
                if razas & ALIANZA and not razas & HORDA:
                    banderas |= SOLO_A
                elif razas & HORDA and not razas & ALIANZA:
                    banderas |= SOLO_H
            nivel = q["QuestLevel"] if q["QuestLevel"] and q["QuestLevel"] > 0 else q["MinLevel"]
            sig = siguiente.get(qid, [0])[0]
            objs_lua = ", ".join(lua_str(o) for o in objs)
            lineas.append(
                f"[{qid}]={{{lua_str(titulo)},{lua_str(resumen)},{{{objs_lua}}},"
                f"{lua_str(empieza)},{lua_str(entrega)},{previa.get(qid, 0)},{sig},"
                f"{mapa.get(qid, 0)},{nivel or 0},{banderas}}},")
        lineas.append("}")
        salida = RAIZ / "KHAOS" / f"Misiones_{idioma}.lua"
        salida.write_text("\n".join(lineas) + "\n", encoding="utf-8")
        print(f"OK: {salida.name} ({salida.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
