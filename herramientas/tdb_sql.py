"""Lector mínimo de volcados SQL de TrinityCore (sentencias INSERT INTO ... VALUES)."""
import re

TOKEN = re.compile(r"'((?:[^'\\]|\\.)*)'|(NULL)|(-?[0-9][0-9.eE+-]*)|([(),])", re.S)
ESC = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "\\": "\\", "'": "'", '"': '"'}


def _unescape(s):
    return re.sub(r"\\(.)", lambda m: ESC.get(m.group(1), m.group(1)), s)


def leer_tablas(ruta, tablas):
    """Devuelve {tabla: (columnas, [filas])} para las tablas pedidas."""
    tablas = set(tablas)
    columnas, datos = {}, {t: [] for t in tablas}
    actual = None
    with open(ruta, encoding="utf-8", errors="replace") as f:
        for linea in f:
            if linea.startswith("CREATE TABLE `"):
                nombre = linea.split("`")[1]
                actual = nombre if nombre in tablas else None
                if actual:
                    columnas[actual] = []
                continue
            if actual and linea.startswith("  `"):
                columnas[actual].append(linea.split("`")[1])
                continue
            if linea.startswith("INSERT INTO `"):
                nombre = linea.split("`")[1]
                if nombre not in tablas:
                    continue
                cuerpo = linea[linea.index("VALUES") + 6:]
                fila, dentro = [], False
                for m in TOKEN.finditer(cuerpo):
                    s, nul, num, p = m.groups()
                    if p == "(":
                        fila, dentro = [], True
                    elif p == ")":
                        datos[nombre].append(fila)
                        dentro = False
                    elif p == ",":
                        continue
                    elif dentro:
                        if s is not None or (nul is None and num is None):
                            fila.append(_unescape(s or ""))
                        elif nul:
                            fila.append(None)
                        else:
                            fila.append(float(num) if any(c in num for c in ".eE") else int(num))
    return {t: (columnas.get(t, []), datos[t]) for t in tablas}


def como_dicts(tabla):
    cols, filas = tabla
    return [dict(zip(cols, f)) for f in filas]
