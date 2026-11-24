"""Normalización y raíces de palabras en español para KHAOS.

IMPORTANTE: KHAOS/Lenguaje.lua hace exactamente lo mismo dentro del juego. Si cambias algo
aquí, cámbialo también allí (el entrenamiento comprueba que ambos coinciden).
"""
import re
import unicodedata

# Abreviaturas y formas de chat -> palabra completa.
ABREVIATURAS = {
    "q": "que", "k": "que", "ke": "que", "qe": "que", "xq": "porque", "pq": "porque",
    "porq": "porque", "xk": "porque", "x": "por", "d": "de", "dnd": "donde", "dnde": "donde",
    "tb": "tambien", "tmb": "tambien", "tbn": "tambien", "xa": "para", "pa": "para",
    "toy": "estoy", "nose": "no se", "ntp": "no te preocupes", "npc": "pnj",
    "lvl": "nivel", "lv": "nivel", "nv": "nivel", "nvl": "nivel", "lvel": "nivel",
    "coords": "coordenadas", "coord": "coordenadas", "cords": "coordenadas",
    "mision": "mision", "misio": "mision", "mison": "mision", "msion": "mision",
    "quest": "mision", "qst": "mision", "kest": "mision", "quests": "misiones",
    "wq": "mision del mundo", "wqs": "misiones del mundo", "info": "informacion",
    "porfa": "por favor", "pls": "por favor", "plz": "por favor", "xfa": "por favor",
    "grax": "gracias", "thx": "gracias", "ty": "gracias", "ola": "hola", "wenas": "buenas",
    "aki": "aqui", "aca": "aqui", "alla": "alli", "ahi": "alli", "sig": "siguiente",
    "sgte": "siguiente", "prox": "proxima", "rep": "reputacion", "reput": "reputacion",
}

# Pronombres pegados al verbo: "entregarla" -> "entregar", "dámela" se queda igual.
ENCLITICOS = re.compile(r"(ar|er|ir)(se|me|te|nos)?(la|lo|le|las|los|les)?$")

SUFIJOS = sorted("""
amientos imientos amiento imiento aciones uciones adoras adores ancias encias amente
acion ucion adora ador ancia encia mente ando iendo ados idos adas idas aste iste
ado ido ada ida aron ieron aban emos amos imos ais eis aba ian ia ar er ir as es an en os a e o s
""".split(), key=len, reverse=True)


def normalizar(texto):
    texto = unicodedata.normalize("NFD", (texto or "").lower())
    texto = "".join(c for c in texto if unicodedata.category(c) != "Mn")
    texto = re.sub(r"<(mision|npc|zona)>", r" x\1 ", texto)
    texto = re.sub(r"[^a-z0-9 ]+", " ", texto)
    texto = re.sub(r"([a-z])\1{2,}", r"\1", texto)  # "holaaa" -> "hola"
    palabras = []
    for p in texto.split():
        p = re.sub(r"([a-z])\1+$", r"\1", p) if len(p) > 3 else p  # "holaa" -> "hola"
        palabras.extend(ABREVIATURAS.get(p, p).split())
    return palabras


def raiz(p):
    if len(p) <= 3 or p.startswith("x") and p in ("xmision", "xnpc", "xzona") or p.isdigit():
        return p
    m = ENCLITICOS.search(p)
    if m and (m.group(2) or m.group(3)) and len(p) - len(m.group(0)) >= 3:
        p = p[: m.start()] + m.group(1)
    for s in SUFIJOS:
        if p.endswith(s) and len(p) - len(s) >= 3:
            return p[: -len(s)]
    return p


def rasgos(texto):
    """Rasgos para el clasificador: raíces sueltas y pares de raíces seguidas."""
    r = [raiz(p) for p in normalizar(texto)]
    out = list(r)
    out += [r[i] + "_" + r[i + 1] for i in range(len(r) - 1)]
    out.append("^" + r[0] if r else "^")
    return out
