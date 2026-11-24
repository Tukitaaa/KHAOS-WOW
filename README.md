# KHAOS

**Asistente de misiones para World of Warcraft: Legion 7.3.5** (interfaz 70300).

Pregúntale en el juego, con tus propias palabras y sin internet, cosas como
*"¿cómo hago esta misión?"*, *"¿a quién se la entrego?"* o *"¿qué misiones hay en Suramar?"*.
KHAOS entiende qué quieres saber y te responde con datos de las 5.550 misiones de Legion.

```
> ya la terminé, ¿a quién se la doy?
(entendí: dónde entregarla - Suministros caídos del cielo)
Misión: Suministros caídos del cielo  (nivel 98, Tormenheim)
Se entrega a: Mishka
Entregar en: Tormenheim 10.6, 28.4
```

---

## Instalación

1. Descarga el repositorio (botón verde **Code → Download ZIP**) y descomprímelo.
2. Copia la carpeta **`KHAOS`** (la que contiene `KHAOS.toc`) en:
   ```
   World of Warcraft/Interface/AddOns/
   ```
   Debe quedar así: `Interface/AddOns/KHAOS/KHAOS.toc`
3. Entra al juego y activa **KHAOS** en la lista de addons (sale en rojo).

> Si tenías instalada una versión antigua llamada `GuiaLegion`, bórrala.

---

## Comandos

| Comando | Qué hace |
|---|---|
| `/khaos <pregunta>` | Pregunta lo que quieras, como hablarías normalmente |
| `/khaos` | Abre o cierra la ventana de KHAOS (también puedes escribir en la caja de abajo) |
| `/khaos <ID>` | Información de una misión por su número, p. ej. `/khaos 43341` |
| `/khaos misiones` | Tus misiones del registro, con a quién se entrega cada una |
| `/khaos lista` | Temas de las guías escritas (volar, Argus, Suramar...) |
| `/khaos avisos` | Activa o desactiva el aviso en el chat al aceptar una misión |
| `/khaos ayuda` | Ayuda rápida y estadísticas (misiones, cosas aprendidas, zonas calibradas) |

`/guia` y `/kh` funcionan igual que `/khaos`.

---

## Qué le puedes preguntar

KHAOS reconoce **15 tipos de pregunta**, escritas de cualquier forma: con o sin tildes, con faltas de
ortografía, en español de España, latino o rioplatense, y con abreviaturas de chat (`q`, `dnd`, `xq`, `lvl`...).

| Tipo | Ejemplos |
|---|---|
| Cómo se hace | `como hago Unir las Islas` · `no entiendo esta mision` · `ayudame con <misión>` |
| Dónde ir | `dnd queda <misión>` · `a donde tengo que ir` · `coords de <misión>` |
| Quién la da | `quien me da <misión>` · `donde se pilla` · `donde la agarro` |
| Dónde entregarla | `a quien se la doy` · `ya la termine y ahora?` |
| Requisitos / qué va antes | `xq no me sale <misión>` · `que necesito para <misión>` |
| Qué sigue | `y despues?` · `cual es la siguiente` |
| Nivel | `que nivel es <misión>` · `soy 105 puedo hacer <misión>` |
| Qué te falta | `que me falta` · `cuantos bichos me quedan` |
| Tus misiones | `que misiones tengo` · `que hago ahora` |
| Misiones de una zona | `que misiones hay en Suramar` · `que hay para hacer por aca` |
| Dónde está un personaje | `donde esta Khadgar` · `no encuentro a <personaje>` |
| Guías generales | `como desbloqueo volar` · `como llego a Argus` |
| Saludo, ayuda, gracias | `hola` · `que podes hacer` · `gracias crack` |

**Recuerda la conversación.** Si preguntas por una misión y después dices *"¿y dónde la entrego?"* o
*"¿y después?"*, sabe que sigues con la misma. Si no nombras ninguna, usa la última que aceptaste.

En gris verás **(entendí: ...)** para saber cómo interpretó tu pregunta. Si alguna vez entiende mal,
anota la frase y añádela al entrenamiento (ver más abajo).

---

## Qué sabe

- **5.550 misiones de Legion**: nombre, nivel, zona, objetivo, pasos, a quién se entrega, la misión anterior
  y la siguiente de la cadena, y si es solo de Horda o de Alianza. En español de España, español latino e
  inglés; usa el idioma de tu cliente.
- **Tu registro en vivo**: lee tus misiones activas y tu progreso real (qué objetivos te faltan).
- **Coordenadas**: sabe dónde están los objetivos de unas 3.900 misiones. La primera vez que entras en
  una zona, camina un poco en distintas direcciones: KHAOS se calibra solo y desde ahí te dice
  *"Ve a: Tormenheim 11.8, 30.9"*.
- **Aprende jugando**: cada vez que un personaje te ofrece una misión o se la entregas, KHAOS guarda su
  nombre y su posición. Lo aprendido vale para todos tus personajes.
- **Aviso automático**: al aceptar una misión te muestra en el chat a dónde ir, a quién entregarla y qué viene después.
- **Guías escritas** sobre temas generales: volar (Pionero), misiones del mundo, arma artefacto, Suramar,
  Argus y la Torre del Mago.

### Limitaciones

- Un addon de WoW **no puede usar internet ni un modelo de IA**: todo funciona dentro del juego con la base
  de datos y el clasificador que lleva el addon.
- La base de datos casi nunca dice **quién da** cada misión. Cuando no lo sabe, KHAOS indica quién entrega la
  misión anterior ("probablemente te la da..."), y lo aprende de verdad en cuanto la aceptas.
- Las guías escritas son resúmenes propios hechos de memoria: conviene revisarlas.

---

## Para desarrolladores

Hace falta **Python 3**. Todos los comandos se ejecutan desde la raíz del repositorio.

### Entrenar el clasificador (entender más formas de preguntar)

1. Añade frases en [`guias/intenciones.txt`](guias/intenciones.txt). El formato está explicado al
   principio del archivo; por ejemplo `{donde|dónde} {queda|está} <mision>` genera todas las combinaciones.
2. Entrena:
   ```
   python3 herramientas/entrenar_intenciones.py
   ```
   Te dice el porcentaje de acierto con [`guias/intenciones_prueba.txt`](guias/intenciones_prueba.txt)
   (preguntas que no se usan para entrenar) y genera `KHAOS/Modelo.lua`.

### Añadir o editar guías

1. Escribe en `guias/*.txt` (formato al principio de [`guias/progresion.txt`](guias/progresion.txt)).
2. `python3 herramientas/construir_bd.py` → genera `KHAOS/Datos.lua`.

### Ver las preguntas que KHAOS no supo responder

```
python3 herramientas/construir_bd.py --pendientes "RUTA_WOW/WTF/Account/TU_CUENTA/SavedVariables/KHAOS.lua"
```

### Regenerar la base de misiones

Necesitas la base libre de TrinityCore **TDB 735.00** ([descarga](https://github.com/TrinityCore/TrinityCore/releases/tag/TDB735.00)),
descomprimida:

```
python3 herramientas/importar_tdb.py RUTA/TDB_world_735.00_2018_02_19.sql
```

Genera `KHAOS/Misiones_esES.lua`, `Misiones_esMX.lua`, `Misiones_enUS.lua` y `Puntos.lua`.

### Estructura

```
KHAOS/                      el addon (esto es lo que va en Interface/AddOns)
  KHAOS.toc
  Lenguaje.lua              normalización y clasificador de intenciones
  Entender.lua              detecta misión/zona/personaje, contexto y respuestas
  Misiones.lua              búsqueda y datos de misiones
  Calibrar.lua              calibración de coordenadas por zona
  Aprender.lua              aprende quién da y recibe cada misión
  Ventana.lua               ventana, comandos y avisos
  Nucleo.lua                búsqueda en guías y registro de misiones
  Modelo.lua, Datos.lua, Misiones_*.lua, Puntos.lua   (generados)
herramientas/               scripts de Python
guias/                      guías escritas y corpus de entrenamiento
```

`herramientas/texto_es.py` y `KHAOS/Lenguaje.lua` deben hacer exactamente lo mismo: si cambias la
normalización en uno, cámbiala también en el otro.

---

## Créditos

- Datos de misiones: [TrinityCore](https://github.com/TrinityCore/TrinityCore) TDB 735.00 (licencia GPL).
- Autor: puyi.
