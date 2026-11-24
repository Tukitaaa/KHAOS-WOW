# KHAOS (versión 0.7) para WoW Legion 7.3.5

Addon que responde dentro del juego, sin internet, a preguntas como
"¿cómo desbloqueo volar?" o "¿cómo hago esta misión?".

## Instalar
Copia la carpeta `KHAOS/KHAOS` (la que contiene `KHAOS.toc`) en
`World of Warcraft/Interface/AddOns/`. Debe quedar así:
`Interface/AddOns/KHAOS/KHAOS.toc`

## Usar
- `/khaos <pregunta>` (o `/guia`, `/kh`) por ejemplo `/khaos como desbloqueo volar`
- `/khaos misiones` guías de las misiones que llevas en el registro
- `/khaos lista` todos los temas de la base
- `/khaos` abre o cierra la ventana; también puedes escribir abajo en ella.

Si la pregunta contiene el nombre de una misión de tu registro, el addon muestra sus
objetivos (leídos del propio juego) y, si existe, la guía de esa misión.

## Cómo entiende las preguntas (v0.7)
KHAOS ya no busca solo palabras: entiende **qué quieres saber**. Tiene un clasificador entrenado
con unas 17.500 formas de preguntar (España, latino, rioplatense, abreviaturas de chat como
"q", "dnd", "xq", "lvl") que distingue 15 tipos de pregunta:

cómo se hace · dónde ir · quién la da · dónde entregarla · qué va antes / requisitos ·
qué sigue · nivel · qué te falta · tus misiones · misiones de una zona · dónde está un personaje ·
guías (volar, Argus...) · saludo · ayuda · gracias

Además reconoce de qué hablas: el nombre de una misión (aunque esté mal escrito), su ID, una
zona ("qué hay en Suramar", "qué hay por aquí") o un personaje ("dónde está Khadgar"). Y recuerda
la conversación: si preguntas "cómo hago Unir las Islas" y luego "¿y dónde la entrego?", sabe que
sigues hablando de la misma. Si no nombras ninguna, usa la última que aceptaste.

En gris verás "(entendí: ...)" para saber cómo interpretó tu pregunta.

**Entrenarlo más:** añade frases en `guias/intenciones.txt` (hay instrucciones dentro) y ejecuta
`python3 herramientas/entrenar_intenciones.py`. El script te dice el porcentaje de acierto con
las preguntas de `guias/intenciones_prueba.txt`, que no se usan para entrenar.

## Base completa de misiones (5.550 misiones de Legion)
KHAOS trae todas las misiones de Legion sacadas de la base libre de TrinityCore 7.3.5 (GPL),
en español de España (esES), español latino (esMX) e inglés (para otros idiomas). Usa sola
la de tu cliente. Para cada misión sabe: nombre, nivel, zona, objetivo, pasos, a quién se
entrega, la misión anterior de la cadena y la siguiente. También puedes buscar por número de ID:
`/khaos 43341`.

Limitación: esa base casi no dice qué PNJ *da* cada misión, ni trae coordenadas. Cuando no lo sabe,
KHAOS pone "Probablemente te la da" con quien entrega la misión anterior.

**KHAOS aprende jugando:** cada vez que un personaje te ofrece una misión o se la entregas,
KHAOS guarda su nombre, la zona y las coordenadas. Desde ese momento, al preguntar por esa
misión verás "Te la da: Nombre (Zona 45.2, 61.9)". Lo aprendido se comparte entre todos tus
personajes de la cuenta (se guarda en SavedVariables/KHAOS.lua).

**Coordenadas que se calibran solas:** la base sabe dónde están los objetivos de unas 3.900
misiones, pero en coordenadas del mundo. Mientras caminas por una zona, KHAOS compara tu posición
en el mundo con tu posición en el mapa. Con unos pocos pasos en distintas direcciones ya sabe
convertirlas y te dice "Ve a: Tormenheim 11.8, 30.9". Cada zona se calibra una sola vez, y sirve
para todos tus personajes.

**Aviso al aceptar una misión:** sale en el chat un resumen (dónde ir, a quién entregarla, qué
viene después). Se apaga o enciende con `/khaos avisos`.

Para regenerar la base (por ejemplo con otra versión de la TDB):
`python3 herramientas/importar_tdb.py RUTA/TDB_world_735.00_2018_02_19.sql`

## Si preguntas algo que no está
- Entiende faltas de ortografía ("bolar" encuentra "volar").
- Si no encuentra nada, te propone temas parecidos y anota la pregunta.
- Para ver las preguntas anotadas (después de salir del juego o hacer /reload):
  `python3 herramientas/construir_bd.py --pendientes "RUTA_WOW/WTF/Account/TU_CUENTA/SavedVariables/KHAOS.lua"`
  Escribe guías para las que más se repitan y vuelve a generar la base.

## Cómo "aprende" (añadir guías)
1. Escribe guías en `guias/*.txt` (mira el formato al principio de `progresion.txt`).
   Usa `misiones:` con el nombre exacto de la misión en tu idioma del cliente, o mejor
   `ids:` con el ID de la misión, para que el addon la detecte en tu registro.
2. Ejecuta `python3 herramientas/construir_bd.py`
3. Esto regenera `KHAOS/Datos.lua`. Escribe `/reload` en el juego.

## Notas
- Un addon no puede conectarse a internet ni ejecutar un modelo de IA: la "IA" es una
  búsqueda por palabras clave con pesos sobre la base que tú generas.
- Las 7 guías de ejemplo son resúmenes propios escritos de memoria: revisa los datos
  antes de fiarte de ellos.
- No copies textos de guías o comentarios de webs (Wowhead, etc.): resume con tus palabras.
