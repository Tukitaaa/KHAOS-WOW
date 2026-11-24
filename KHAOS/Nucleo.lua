-- KHAOS: búsqueda en la base de guías + lectura del registro de misiones.
-- Compatible con la API de WoW 7.3.5 (Lua 5.1).
local _, ns = ...

-- Tildes y eñes a letras simples, para que "misión" y "mision" coincidan.
local TILDES = {
  ["á"]="a", ["é"]="e", ["í"]="i", ["ó"]="o", ["ú"]="u", ["ü"]="u", ["ñ"]="n",
  ["Á"]="a", ["É"]="e", ["Í"]="i", ["Ó"]="o", ["Ú"]="u", ["Ü"]="u", ["Ñ"]="n",
}

local VACIAS = {}
for p in ([[a al algo como con de del el en es esta este esto hay la las le lo los
  mas me mi no o para pero por que se si sin su sus te tu un una uno y ya hacer hago
  puedo donde cual cuando mision misiones quest the of to and in for is how do i]]):gmatch("%S+") do
  VACIAS[p] = true
end

function ns.Normalizar(texto)
  texto = (texto or ""):lower()
  for con, sin in pairs(TILDES) do
    texto = texto:gsub(con, sin)
  end
  return texto
end

function ns.Palabras(texto)
  local lista = {}
  for p in ns.Normalizar(texto):gmatch("[%w']+") do
    if #p > 2 and not VACIAS[p] then
      lista[#lista + 1] = p
    end
  end
  return lista
end

---------------------------------------------------------------------------
-- Registro de misiones (API 7.3.5)
---------------------------------------------------------------------------
function ns.MisionesActivas()
  local misiones = {}
  if not GetNumQuestLogEntries then return misiones end
  local seleccionPrevia = GetQuestLogSelection and GetQuestLogSelection()
  local total = GetNumQuestLogEntries()
  for i = 1, total do
    local titulo, nivel, _, esCabecera, _, completada, _, questID = GetQuestLogTitle(i)
    if titulo and not esCabecera then
      local objetivos = {}
      for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
        local texto, _, hecho = GetQuestLogLeaderBoard(j, i)
        if texto then
          objetivos[#objetivos + 1] = { texto = texto, hecho = hecho }
        end
      end
      local resumen
      if SelectQuestLogEntry and GetQuestLogQuestText then
        SelectQuestLogEntry(i)
        local _, textoObjetivos = GetQuestLogQuestText()
        resumen = textoObjetivos
      end
      misiones[#misiones + 1] = {
        indice = i, titulo = titulo, nombre = ns.Normalizar(titulo), nivel = nivel,
        completada = completada == 1 or completada == true, questID = questID,
        objetivos = objetivos, resumen = resumen,
      }
    end
  end
  if seleccionPrevia and SelectQuestLogEntry then SelectQuestLogEntry(seleccionPrevia) end
  return misiones
end

-- ¿Esta guía habla de alguna misión que tienes en el registro?
local function MisionDeGuia(guia, misiones)
  for _, m in ipairs(misiones) do
    if guia.questIDs and m.questID and guia.questIDs[m.questID] then return m end
    for _, nombre in ipairs(guia.misiones or {}) do
      if m.nombre == nombre or m.nombre:find(nombre, 1, true) then return m end
    end
  end
end

---------------------------------------------------------------------------
-- Búsqueda
---------------------------------------------------------------------------
-- Distancia de edición (cuántas letras hay que cambiar para pasar de a a b).
-- Sirve para entender faltas de ortografía: "bolar" ~ "volar".
local function Distancia(a, b, limite)
  local la, lb = #a, #b
  if math.abs(la - lb) > limite then return limite + 1 end
  local previa = {}
  for j = 0, lb do previa[j] = j end
  for i = 1, la do
    local actual, minimo = { [0] = i }, i
    local ca = a:byte(i)
    for j = 1, lb do
      local coste = (ca == b:byte(j)) and 0 or 1
      local v = math.min(previa[j] + 1, actual[j - 1] + 1, previa[j - 1] + coste)
      actual[j] = v
      if v < minimo then minimo = v end
    end
    if minimo > limite then return limite + 1 end
    previa = actual
  end
  return previa[lb]
end

ns.Distancia = Distancia

local function Tolerancia(palabra)
  if #palabra >= 8 then return 2 elseif #palabra >= 4 then return 1 end
  return 0
end

-- Peso de una palabra de la pregunta dentro de una guía:
-- exacta = peso completo; prefijo o con una falta = mitad.
local function PesoPalabra(guia, p)
  local peso = guia.indice[p]
  if peso then return peso end
  local mejor, tol = 0, Tolerancia(p)
  if tol == 0 then return 0 end
  for clave, w in pairs(guia.indice) do
    if w > mejor and #clave >= 4 then
      if clave:sub(1, #p) == p or p:sub(1, #clave) == clave
         or Distancia(p, clave, tol) <= tol then
        mejor = w
      end
    end
  end
  return mejor / 2
end
-- Puntúa cada guía según las palabras de la pregunta. Coincidencia exacta vale
-- el peso completo; coincidencia parcial (prefijo de 4+ letras) vale la mitad.
-- Si la guía trata una misión que llevas en el registro, gana puntos extra.
function ns.Buscar(pregunta, misiones, maximo)
  local consulta = ns.Palabras(pregunta)
  local resultados = {}
  for _, guia in ipairs(ns.Guias or {}) do
    local puntos = 0
    for _, p in ipairs(consulta) do
      puntos = puntos + PesoPalabra(guia, p)
    end
    local mision = misiones and MisionDeGuia(guia, misiones)
    if mision and puntos > 0 then puntos = puntos + 4 end
    if puntos > 0 then
      resultados[#resultados + 1] = { guia = guia, puntos = puntos, mision = mision }
    end
  end
  table.sort(resultados, function(a, b) return a.puntos > b.puntos end)
  local top = {}
  -- Solo respuestas razonablemente buenas comparadas con la mejor.
  for i = 1, math.min(maximo or 3, #resultados) do
    if resultados[i].puntos >= resultados[1].puntos * 0.4 then top[#top + 1] = resultados[i] end
  end
  return top
end

-- Misiones del registro cuyo nombre aparece en la pregunta (p. ej. "como hago Uniendo las islas").
function ns.MisionesEnPregunta(pregunta, misiones)
  local q = ns.Normalizar(pregunta)
  local encontradas = {}
  for _, m in ipairs(misiones) do
    if #m.nombre >= 4 and q:find(m.nombre, 1, true) then
      encontradas[#encontradas + 1] = m
    end
  end
  return encontradas
end

-- Guías que corresponden a misiones de tu registro.
function ns.GuiasDelRegistro(misiones)
  local lista = {}
  for _, guia in ipairs(ns.Guias or {}) do
    local m = MisionDeGuia(guia, misiones)
    if m then lista[#lista + 1] = { guia = guia, mision = m } end
  end
  return lista
end

-- Cuando no hay respuesta: los temas cuyo título se parece más a la pregunta.
function ns.Sugerencias(pregunta, maximo)
  local consulta = ns.Palabras(pregunta)
  local lista = {}
  for _, guia in ipairs(ns.Guias or {}) do
    local parecido = 0
    for _, p in ipairs(consulta) do
      local limite = math.max(1, math.floor(#p / 3))
      for _, t in ipairs(ns.Palabras(guia.titulo .. " " .. table.concat(guia.claves or {}, " "))) do
        local d = Distancia(p, t, limite)
        if #p >= 4 and d <= limite then parecido = math.max(parecido, limite + 1 - d) end
      end
    end
    if parecido > 0 then lista[#lista + 1] = { guia = guia, parecido = parecido } end
  end
  table.sort(lista, function(a, b) return a.parecido > b.parecido end)
  local top = {}
  for i = 1, math.min(maximo or 3, #lista) do top[i] = lista[i].guia end
  return top
end

-- Guarda las preguntas sin respuesta (se graban en WTF/.../SavedVariables/KHAOS.lua
-- al salir del juego o con /reload). El script construir_bd.py --pendientes las lista.
function ns.AnotarSinRespuesta(pregunta)
  KhaosDB = KhaosDB or {}
  KhaosDB.sinRespuesta = KhaosDB.sinRespuesta or {}
  local clave = ns.Normalizar(pregunta)
  KhaosDB.sinRespuesta[clave] = (KhaosDB.sinRespuesta[clave] or 0) + 1
end
