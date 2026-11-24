-- KHAOS: entiende la pregunta y responde según lo que quieres saber.
--   1. Busca de qué hablas: una misión (por nombre, ID o "esta"), una zona o un personaje.
--   2. Cambia ese nombre por una marca (xmision, xzona, xnpc) y clasifica la frase con el
--      modelo entrenado (Modelo.lua) para saber QUÉ quieres: dónde, quién la da, qué sigue...
--   3. Si no dices de qué misión hablas, usa el contexto: la última de la que hablamos, la que
--      sigues en pantalla o la última que aceptaste.
local _, ns = ...

local UI
local function C() UI = UI or ns.UI; return UI end

local ETIQUETAS = {
  pasos = "cómo se hace", donde = "dónde ir", inicio = "quién la da", entrega = "dónde entregarla",
  antes = "qué va antes / requisitos", despues = "qué sigue", nivel = "nivel",
  progreso = "qué te falta", mis_misiones = "tus misiones", zona = "misiones de una zona",
  npc_donde = "dónde está un personaje", guia = "guía", saludo = "saludo", ayuda = "ayuda",
  gracias = "agradecimiento",
}
local NECESITA_MISION = {
  pasos = true, donde = true, inicio = true, entrega = true, antes = true,
  despues = true, nivel = true,
}
local SALUDOS, GRACIAS = {}, {}
for p in ([[hola holi buenas buen buenos dia dias tardes noches hey ey saludos que tal onda hay
  khaos hello hi como estas andas pasa]]):gmatch("%S+") do SALUDOS[p] = true end
for p in ([[gracias muchas mil grax genial perfecto crack sos eres un vale ok dale joya excelente
  buenisimo de una listo entendido te pasaste el mejor]]):gmatch("%S+") do GRACIAS[p] = true end
local VACIAS = {}
for p in ([[a al de del el en la las lo los un una y o que se me te le mi tu su para por con
  sin como es esta este esa ese eso esto mision misiones quest]]):gmatch("%S+") do VACIAS[p] = true end

---------------------------------------------------------------------------
-- Índices (se construyen la primera vez que preguntas)
---------------------------------------------------------------------------
local titulos, df, totalTitulos, vocabTitulos, inverso -- misiones
local zonas -- { {palabras = {...}, mapa = id, nombre = "..."} }
local pnjs, dfPnj -- personajes

local function Contenido(palabras)
  local out = {}
  for _, p in ipairs(palabras) do
    if #p > 2 and not VACIAS[p] then out[#out + 1] = p end
  end
  return out
end

local function IndiceMisiones()
  if titulos then return end
  titulos, df, totalTitulos, vocabTitulos, inverso = {}, {}, 0, {}, {}
  for id, m in pairs(ns.Misiones or {}) do
    local palabras = Contenido(ns.NormalizarFrase(m[1]))
    if #palabras > 0 then
      titulos[id] = palabras
      totalTitulos = totalTitulos + 1
      local vistas = {}
      for _, p in ipairs(palabras) do
        if not vistas[p] then
          vistas[p] = true
          if not df[p] then vocabTitulos[#vocabTitulos + 1] = p; inverso[p] = {} end
          df[p] = (df[p] or 0) + 1
          inverso[p][#inverso[p] + 1] = id
        end
      end
    end
  end
end

local function Idf(p) return math.log(totalTitulos / (df[p] or 1)) end

-- Nombres en otros idiomas para las zonas principales (los IDs están comprobados con la base).
local ALIAS_ZONAS = {
  [1015] = { "azsuna" }, [1017] = { "stormheim", "tormenheim" },
  [1018] = { "valsharah", "val sharah" }, [1024] = { "highmountain", "monte alto", "altamontana" },
  [1033] = { "suramar" }, [1021] = { "broken shore", "costa abrupta", "costa quebrada" },
  [1014] = { "dalaran" },
}

local function IndiceZonas()
  if zonas then return end
  zonas = {}
  local vistos = {}
  local function Agregar(mapa, texto, nombre)
    local palabras = ns.NormalizarFrase(texto)
    local clave = mapa .. ":" .. table.concat(palabras, " ")
    if #palabras > 0 and not vistos[clave] then
      vistos[clave] = true
      zonas[#zonas + 1] = { palabras = palabras, mapa = mapa, nombre = nombre }
    end
  end
  local mapas = {}
  for _, m in pairs(ns.Misiones or {}) do if m[8] and m[8] > 0 then mapas[m[8]] = true end end
  for _, lista in pairs(ns.Puntos or {}) do
    for _, p in ipairs(lista) do mapas[p[1]] = true end
  end
  for mapa in pairs(mapas) do
    local nombre = GetMapNameByID and GetMapNameByID(mapa)
    if nombre and nombre ~= "" then Agregar(mapa, nombre, nombre) end
  end
  for mapa, alias in pairs(ALIAS_ZONAS) do
    local nombre = (GetMapNameByID and GetMapNameByID(mapa)) or alias[1]
    for _, a in ipairs(alias) do Agregar(mapa, a, nombre) end
  end
end

local function IndicePnjs()
  if pnjs then return end
  pnjs, dfPnj = {}, {}
  local function Agregar(nombre, id, rol)
    nombre = nombre:gsub("^~", "")
    if nombre == "" then return end
    local clave = table.concat(ns.NormalizarFrase(nombre), " ")
    local p = pnjs[clave]
    if not p then
      p = { nombre = nombre, palabras = ns.NormalizarFrase(nombre), da = {}, recibe = {} }
      pnjs[clave] = p
      local vistas = {}
      for _, w in ipairs(p.palabras) do
        if not vistas[w] then vistas[w] = true; dfPnj[w] = (dfPnj[w] or 0) + 1 end
      end
    end
    local lista = p[rol]
    lista[#lista + 1] = id
  end
  for id, m in pairs(ns.Misiones or {}) do
    for nombre in (m[4] .. " / "):gmatch("(.-) / ") do Agregar(nombre, id, "da") end
    for nombre in (m[5] .. " / "):gmatch("(.-) / ") do Agregar(nombre, id, "recibe") end
  end
  for id, r in pairs(KhaosDB and KhaosDB.aprendido or {}) do
    if r.da and r.da[1] ~= "" then Agregar(r.da[1], id, "da") end
    if r.recibe and r.recibe[1] ~= "" then Agregar(r.recibe[1], id, "recibe") end
  end
end

---------------------------------------------------------------------------
-- Detectar de qué hablas
---------------------------------------------------------------------------
local function Igual(a, b)
  if a == b then return true end
  if #a >= 5 and #b >= 5 and ns.Distancia(a, b, 1) <= 1 then return true end
  return false
end

-- Busca la secuencia "objetivo" dentro de "palabras" (permitiendo una falta por palabra larga).
local function Secuencia(palabras, objetivo)
  local n, m = #palabras, #objetivo
  if m == 0 or m > n then return end
  for i = 1, n - m + 1 do
    local ok = true
    for j = 1, m do
      if not Igual(palabras[i + j - 1], objetivo[j]) then ok = false; break end
    end
    if ok then
      local pos = {}
      for j = 1, m do pos[#pos + 1] = i + j - 1 end
      return pos
    end
  end
end

local function EnLog(id, log)
  for _, m in ipairs(log or {}) do if m.questID == id then return m end end
end

local function DetectarMision(palabras, log)
  IndiceMisiones()
  local res = {}
  -- 1) Número de ID.
  for i, p in ipairs(palabras) do
    local n = tonumber(p)
    if n and ns.Misiones and ns.Misiones[n] then
      res[#res + 1] = { tipo = "mision", id = n, pos = { i }, fuerza = 2 }
    end
  end
  -- 2) Títulos de tu registro, completos.
  for _, m in ipairs(log or {}) do
    local pos = Secuencia(palabras, ns.NormalizarFrase(m.titulo))
    if pos and m.questID then
      res[#res + 1] = { tipo = "mision", id = m.questID, pos = pos, fuerza = 1.5 + #pos / 100 }
    end
  end
  -- 3) Toda la base: palabras del título que aparecen en la pregunta (pesadas por rareza).
  local candidatos = {}
  for i, p in ipairs(palabras) do
    if #p > 2 and not VACIAS[p] then
      local formas = {}
      if df[p] then formas[#formas + 1] = p end
      if #p >= 5 and not df[p] then
        for _, v in ipairs(vocabTitulos) do
          if #v >= 5 and math.abs(#v - #p) <= 1 and ns.Distancia(p, v, 1) <= 1 then
            formas[#formas + 1] = v
          end
        end
      end
      for _, f in ipairs(formas) do
        if df[f] <= 400 then candidatos[f] = candidatos[f] or {}; candidatos[f][#candidatos[f] + 1] = i end
      end
    end
  end
  local porMision = {}
  for forma, posiciones in pairs(candidatos) do
    for _, id in ipairs(inverso[forma]) do
      local e = porMision[id] or { pos = {}, idf = 0, vistas = {} }
      if not e.vistas[forma] then
        e.vistas[forma] = true
        e.idf = e.idf + Idf(forma)
        for _, q in ipairs(posiciones) do e.pos[#e.pos + 1] = q end
      end
      porMision[id] = e
    end
  end
  local faccion = UnitFactionGroup and UnitFactionGroup("player")
  for id, e in pairs(porMision) do
    local total = 0
    for _, w in ipairs(titulos[id]) do total = total + Idf(w) end
    local cobertura = total > 0 and e.idf / total or 0
    if cobertura >= 0.7 and e.idf >= 4 then
      local m = ns.Misiones[id]
      local b = m[10] or 0
      local fuerza = cobertura + e.idf / 100
      if EnLog(id, log) then fuerza = fuerza + 0.3 end
      if (faccion == "Alliance" and b % 8 >= 4) or (faccion == "Horde" and b % 4 >= 2) then
        fuerza = fuerza - 0.2
      end
      if b % 2 == 1 then fuerza = fuerza - 0.05 end
      if m[6] > 0 or m[7] > 0 then fuerza = fuerza + 0.02 end
      table.sort(e.pos)
      res[#res + 1] = { tipo = "mision", id = id, pos = e.pos, fuerza = fuerza }
    end
  end
  table.sort(res, function(a, b) return a.fuerza > b.fuerza end)
  return res[1]
end

local function DetectarZona(palabras)
  IndiceZonas()
  local mejor
  for _, z in ipairs(zonas) do
    local pos = Secuencia(palabras, z.palabras)
    if pos and (not mejor or #pos > #mejor.pos) then
      mejor = { tipo = "zona", mapa = z.mapa, nombre = z.nombre, pos = pos }
    end
  end
  return mejor
end

local function DetectarPnj(palabras)
  IndicePnjs()
  local mejor
  for _, p in pairs(pnjs) do
    local pos = Secuencia(palabras, p.palabras)
    local puntos = pos and (10 + #pos)
    if not pos then
      -- Solo una palabra del nombre, si es rara (p. ej. "khadgar" en "Archimago Khadgar").
      for _, w in ipairs(p.palabras) do
        if #w >= 5 and (dfPnj[w] or 0) <= 3 and not VACIAS[w] then
          for i, q in ipairs(palabras) do
            if q == w then pos, puntos = { i }, 5 - (dfPnj[w] or 0); break end
          end
        end
        if pos then break end
      end
    end
    if pos and (not mejor or puntos > mejor.puntos) then
      mejor = { tipo = "npc", pnj = p, pos = pos, puntos = puntos }
    end
  end
  return mejor
end

-- Sustituye las palabras de una entidad por su marca (xmision, xzona, xnpc).
local function ConMarca(palabras, entidad)
  local quitar = {}
  for _, i in ipairs(entidad.pos) do quitar[i] = true end
  local primero, ultimo = entidad.pos[1], entidad.pos[#entidad.pos]
  for i = primero, ultimo do
    if VACIAS[palabras[i]] then quitar[i] = true end
  end
  local out, puesta = {}, false
  local marca = ({ mision = "xmision", zona = "xzona", npc = "xnpc" })[entidad.tipo]
  for i, p in ipairs(palabras) do
    if quitar[i] then
      if not puesta then out[#out + 1] = marca; puesta = true end
    else
      out[#out + 1] = p
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Contexto: ¿de qué misión hablamos si no la nombras?
---------------------------------------------------------------------------
ns.contexto = ns.contexto or {}

local function Ahora() return GetTime and GetTime() or 0 end

local function MisionDelContexto(log)
  local candidatos = {}
  if ns.contexto.mision then
    candidatos[#candidatos + 1] = { ns.contexto.mision, ns.contexto.hora or 0 }
  end
  if KhaosDB and KhaosDB.ultimaAceptada and EnLog(KhaosDB.ultimaAceptada, log) then
    candidatos[#candidatos + 1] = { KhaosDB.ultimaAceptada, ns.ultimaAceptadaHora or -1 }
  end
  table.sort(candidatos, function(a, b) return a[2] > b[2] end)
  if candidatos[1] then return candidatos[1][1] end
  local seguida = GetSuperTrackedQuestID and GetSuperTrackedQuestID()
  if seguida and seguida > 0 and EnLog(seguida, log) then return seguida end
  if #log == 1 then return log[1].questID end
end

local function Recordar(id)
  ns.contexto.mision, ns.contexto.hora = id, Ahora()
end

---------------------------------------------------------------------------
-- Respuestas
---------------------------------------------------------------------------
local function Titulo(id) local m = ns.Misiones[id]; return m and m[1] or ("#" .. id) end

local function Cabecera(id)
  local lineas = ns.LineasMision(id)
  if lineas then C().EscribirLineas({ lineas[1] }) end
end

local function Linea(texto) C().Escribir(texto) end

local function Quien(id, tipo)
  local m = ns.Misiones[id]
  local aprendido = ns.Aprendido and ns.Aprendido(id, tipo)
  if aprendido then return aprendido, true end
  local campo = (tipo == "da") and m[4] or m[5]
  if campo ~= "" then
    if campo:sub(1, 1) == "~" then return campo:sub(2), false, true end
    return campo, true
  end
end

local function Puntos(id, tipo)
  local out = {}
  for _, l in ipairs(ns.LineasPuntos(id)) do
    local esEntrega = l[2]:find("^Entregar") ~= nil
    if l[1] ~= "donde" or tipo == nil or (tipo == 1) == esEntrega then out[#out + 1] = l end
  end
  return out
end

local R = {}

function R.pasos(id, log)
  local enLog = EnLog(id, log)
  if enLog then C().MostrarMisionLog(enLog) else C().MostrarMisionBase(id) end
end

function R.donde(id, log)
  Cabecera(id)
  local lineas = Puntos(id, 0)
  if #lineas == 0 then lineas = Puntos(id) end
  if #lineas > 0 then
    C().EscribirLineas(lineas)
  else
    Linea("No tengo la ubicación de esta misión en la base.")
  end
  local enLog = EnLog(id, log)
  if enLog then
    for _, o in ipairs(enLog.objetivos) do
      if not o.hecho then Linea("   " .. C().GRIS .. "[ ] " .. C().FIN .. o.texto) end
    end
  end
end

function R.inicio(id)
  Cabecera(id)
  local quien, seguro, probable = Quien(id, "da")
  if quien and seguro then
    Linea("Te la da: " .. quien)
  elseif probable then
    Linea("La base no dice quién la da. Lo más probable: " .. quien ..
      " (quien entrega la misión anterior).")
  else
    Linea("La base no dice quién la da. Cuando la cojas, KHAOS lo aprenderá.")
  end
  local m = ns.Misiones[id]
  if m[6] > 0 then Linea("Antes tienes que hacer: " .. Titulo(m[6])) end
  for _, l in ipairs(Puntos(id, 0)) do
    if l[1] ~= "donde" then C().EscribirLineas({ l }) end
  end
end

function R.entrega(id, log)
  Cabecera(id)
  local quien = Quien(id, "recibe")
  Linea("Se entrega a: " .. (quien or "la base no lo dice"))
  local lineas = Puntos(id, 1)
  local hay = false
  for _, l in ipairs(lineas) do if l[1] == "donde" then hay = true end end
  if hay then C().EscribirLineas(lineas) elseif #lineas > 0 then C().EscribirLineas(lineas) end
  local enLog = EnLog(id, log)
  if enLog then
    if enLog.completada then
      Linea(C().VERDE .. "¡Ya la tienes completa, puedes entregarla!" .. C().FIN)
    else
      Linea("Todavía te falta:")
      for _, o in ipairs(enLog.objetivos) do
        if not o.hecho then Linea("   " .. C().GRIS .. "[ ] " .. C().FIN .. o.texto) end
      end
    end
  end
end

function R.antes(id)
  Cabecera(id)
  local m = ns.Misiones[id]
  local cadena, actual, vistas = {}, m[6], {}
  while actual and actual > 0 and #cadena < 6 and not vistas[actual] do
    vistas[actual] = true
    table.insert(cadena, 1, Titulo(actual))
    actual = ns.Misiones[actual] and ns.Misiones[actual][6]
  end
  if #cadena > 0 then
    Linea("Antes tienes que hacer (en orden): " .. table.concat(cadena, " > "))
  else
    Linea("No tengo registrada ninguna misión previa. Puede depender de tu nivel, de una " ..
      "reputación o de avanzar la historia de la zona.")
  end
  if m[9] and m[9] > 0 then
    local tu = UnitLevel and UnitLevel("player")
    Linea("Nivel: " .. m[9] .. (tu and (" (tú eres " .. tu .. ")") or ""))
  end
  local b = m[10] or 0
  if b % 4 >= 2 then Linea("Es solo para la Alianza.") end
  if b % 8 >= 4 then Linea("Es solo para la Horda.") end
  local quien, seguro = Quien(id, "da")
  if quien then Linea((seguro and "Te la da: " or "Probablemente te la da: ") .. quien) end
end

function R.despues(id)
  Cabecera(id)
  local m = ns.Misiones[id]
  if m[7] and m[7] > 0 then
    Linea("Después sigue con:")
    C().MostrarMisionBase(m[7])
    Recordar(m[7])
    return true
  end
  Linea("No tengo registrada ninguna misión que siga a esta. Habla con " ..
    ((Quien(id, "recibe")) or "quien te la recoge") .. " al entregarla: suele darte la siguiente.")
end

function R.nivel(id)
  Cabecera(id)
  local m = ns.Misiones[id]
  local tu = UnitLevel and UnitLevel("player")
  if m[9] and m[9] > 0 then
    local texto = "Es de nivel " .. m[9] .. "."
    if tu then
      texto = texto .. (tu >= m[9] and " Tú eres " .. tu .. ", puedes hacerla."
        or " Tú eres " .. tu .. ", te faltan " .. (m[9] - tu) .. " niveles.")
    end
    Linea(texto)
  else
    Linea("La base no indica un nivel para esta misión (escala con tu nivel).")
  end
end

local function Progreso(id, log)
  local enLog = id and EnLog(id, log)
  if enLog then C().MostrarMisionLog(enLog); return end
  if id then
    Cabecera(id)
    Linea("No la tienes en tu registro, así que no sé tu progreso.")
    return
  end
  if #log == 0 then Linea("No tienes misiones en el registro."); return end
  for _, m in ipairs(log) do
    local faltan = {}
    for _, o in ipairs(m.objetivos) do if not o.hecho then faltan[#faltan + 1] = o.texto end end
    if m.completada then
      Linea(C().VERDE .. "[x] " .. m.titulo .. " - ¡lista para entregar!" .. C().FIN)
    else
      Linea(C().AMARILLO .. m.titulo .. C().FIN .. (#faltan > 0 and (": " .. table.concat(faltan, "; ")) or ""))
    end
  end
end

local function MapaActual()
  if WorldMapFrame and WorldMapFrame:IsShown() then return GetCurrentMapAreaID and GetCurrentMapAreaID() end
  if SetMapToCurrentZone then SetMapToCurrentZone() end
  return GetCurrentMapAreaID and GetCurrentMapAreaID()
end

local function Zona(mapa, nombre)
  nombre = nombre or (GetMapNameByID and GetMapNameByID(mapa)) or ("mapa " .. tostring(mapa))
  local faccion = UnitFactionGroup and UnitFactionGroup("player")
  local lista, mundo = {}, 0
  for id, m in pairs(ns.Misiones or {}) do
    if m[8] == mapa then
      local b = m[10] or 0
      local otra = (faccion == "Alliance" and b % 8 >= 4) or (faccion == "Horde" and b % 4 >= 2)
      if b % 2 == 1 then
        mundo = mundo + 1
      elseif not otra then
        lista[#lista + 1] = id
      end
    end
  end
  table.sort(lista, function(a, b)
    local ma, mb = ns.Misiones[a], ns.Misiones[b]
    if (ma[9] or 0) ~= (mb[9] or 0) then return (ma[9] or 0) < (mb[9] or 0) end
    return a < b
  end)
  if #lista == 0 and mundo == 0 then
    Linea("No tengo misiones registradas en " .. nombre .. ".")
    return
  end
  Linea(C().AMARILLO .. nombre .. ": " .. #lista .. " misiones" ..
    (mundo > 0 and (" y " .. mundo .. " misiones del mundo") or "") .. C().FIN)
  local inicios = {}
  for _, id in ipairs(lista) do
    local m = ns.Misiones[id]
    if m[6] == 0 and m[7] > 0 then inicios[#inicios + 1] = id end
  end
  if #inicios > 0 then
    Linea("Empiezan cadenas de historia:")
    for i = 1, math.min(8, #inicios) do
      local m = ns.Misiones[inicios[i]]
      local quien = Quien(inicios[i], "da")
      Linea("   " .. C().AZUL .. "•" .. C().FIN .. " " .. m[1] ..
        (quien and (C().GRIS .. " - " .. quien .. C().FIN) or ""))
    end
  end
  Linea("Pregúntame por cualquiera de ellas para ver los detalles.")
end

local function PnjDonde(p)
  Linea(C().AMARILLO .. p.nombre .. C().FIN)
  local encontrado = false
  for id, r in pairs(KhaosDB and KhaosDB.aprendido or {}) do
    for _, tipo in ipairs({ "da", "recibe" }) do
      if not encontrado and r[tipo] and r[tipo][1] == p.nombre then
        local texto = ns.Aprendido(id, tipo)
        if texto then Linea("Lo viste en: " .. texto); encontrado = true end
      end
    end
  end
  if not encontrado then
    for _, id in ipairs(p.recibe) do
      for _, l in ipairs(Puntos(id, 1)) do
        if not encontrado and l[1] == "donde" then
          Linea("Está en: " .. l[2]:gsub("^Entregar en: ", ""))
          encontrado = true
        end
      end
    end
  end
  if not encontrado then
    for _, id in ipairs(p.recibe) do
      local mapa = ns.Misiones[id][8]
      local zona = mapa and mapa > 0 and GetMapNameByID and GetMapNameByID(mapa)
      if zona and not encontrado then Linea("Suele estar en: " .. zona); encontrado = true end
    end
  end
  if not encontrado then Linea("No sé dónde está todavía.") end
  local lista = {}
  for _, id in ipairs(p.recibe) do lista[#lista + 1] = Titulo(id) end
  if #lista > 0 then
    Linea(C().GRIS .. "Recoge: " .. table.concat(lista, ", ", 1, math.min(5, #lista)) ..
      (#lista > 5 and "..." or "") .. C().FIN)
  end
end

local function Ayuda()
  Linea("Pregúntame como quieras. Por ejemplo:")
  for _, e in ipairs({ "dónde se hace Unir las Islas", "quién me da esta misión",
    "ya la terminé, ¿a quién se la doy?", "¿y qué sigue?", "qué me falta",
    "qué misiones hay en Suramar", "dónde está Khadgar", "cómo desbloqueo volar" }) do
    Linea("   " .. C().AZUL .. "•" .. C().FIN .. " " .. e)
  end
end

---------------------------------------------------------------------------
-- Entender y responder
---------------------------------------------------------------------------
function ns.Entender(pregunta, log)
  local palabras = ns.NormalizarFrase(pregunta)
  local entidades = {}
  local mision = DetectarMision(palabras, log)
  if mision then entidades[#entidades + 1] = mision end
  local zona = DetectarZona(palabras)
  if zona then entidades[#entidades + 1] = zona end
  local pnj = DetectarPnj(palabras)
  if pnj then entidades[#entidades + 1] = pnj end

  -- Probamos la frase con cada posible entidad marcada y nos quedamos con la más clara.
  local mejor = { entidad = nil }
  local _
  mejor.intencion, mejor.prob, _, mejor.conocidas, mejor.contenido = ns.Clasificar(palabras)
  for _, e in ipairs(entidades) do
    local intencion, prob, _, conocidas = ns.Clasificar(ConMarca(palabras, e))
    local encaja = (e.tipo == "mision" and NECESITA_MISION[intencion]) or (e.tipo == "mision" and intencion == "progreso")
      or (e.tipo == "zona" and intencion == "zona") or (e.tipo == "npc" and intencion == "npc_donde")
    local valor = prob + (encaja and 0.5 or 0) + (e.tipo == "mision" and 0.05 or 0)
    if not mejor.valor or valor > mejor.valor then
      mejor = { entidad = e, intencion = intencion, prob = prob, valor = valor, conocidas = conocidas }
    end
  end
  return mejor, entidades
end

function ns.Responder(pregunta)
  C().Abrir()
  C().Escribir(C().GRIS .. "> " .. pregunta .. C().FIN)
  if not ns.Modelo then return ns.ResponderBusqueda(pregunta, true) end
  local log = ns.MisionesActivas()
  local r, entidades = ns.Entender(pregunta, log)
  -- Mensajes que son solo un saludo o un "gracias".
  local soloSaludo, soloGracias, palabras = true, true, ns.NormalizarFrase(pregunta)
  for _, p in ipairs(palabras) do
    if not SALUDOS[p] then soloSaludo = false end
    if not GRACIAS[p] then soloGracias = false end
  end
  if #palabras > 0 and soloSaludo then r.intencion, r.prob, r.entidad = "saludo", 1, nil; entidades = {} end
  if #palabras > 0 and soloGracias then r.intencion, r.prob, r.entidad = "gracias", 1, nil; entidades = {} end
  -- Nada de la pregunta se parece a lo que KHAOS conoce: no inventamos.
  local desconocida = (r.conocidas or 0) == 0 or
    ((r.contenido or 0) > 0 and (r.conocidas or 0) / r.contenido < 0.5)
  if #entidades == 0 and desconocida and r.intencion ~= "saludo" and r.intencion ~= "gracias" then
    return ns.ResponderBusqueda(pregunta, true)
  end
  local intencion, e = r.intencion, r.entidad
  local id = e and e.tipo == "mision" and e.id or nil
  local mapa = e and e.tipo == "zona" and e.mapa or nil
  local pnj = e and e.tipo == "npc" and e.pnj or nil
  -- Si la mejor lectura no usó una entidad que sí apareció, aún podemos aprovecharla.
  for _, x in ipairs(entidades) do
    if x.tipo == "mision" and not id and NECESITA_MISION[intencion] then id = x.id end
    if x.tipo == "zona" and not mapa and intencion == "zona" then mapa, e = x.mapa, x end
    if x.tipo == "npc" and not pnj and intencion == "npc_donde" then pnj = x.pnj end
  end

  -- Preguntas sobre temas generales (volar, Argus...) cuando no nombras nada concreto.
  if not id and not mapa and not pnj and intencion ~= "saludo" and intencion ~= "gracias"
     and intencion ~= "ayuda" and intencion ~= "mis_misiones" then
    local guias = ns.Buscar(pregunta, log, 2)
    if guias[1] and (guias[1].puntos >= 8 or intencion == "guia") then
      C().Escribir(C().GRIS .. "(entendí: guía)" .. C().FIN)
      for _, g in ipairs(guias) do C().MostrarGuia(g.guia, g.mision) end
      return
    end
  end

  if intencion == "npc_donde" and not pnj and id then intencion = "donde" end
  if intencion == "zona" and not mapa then mapa = MapaActual() end
  if NECESITA_MISION[intencion] and not id then
    -- Sin nombrar misión y sin estar seguros de la pregunta: mejor buscar que inventar.
    if r.prob < 0.6 then return ns.ResponderBusqueda(pregunta, true) end
    id = MisionDelContexto(log)
  end
  if intencion == "progreso" and not id and r.prob < 0.9 then id = MisionDelContexto(log) end

  local de
  if NECESITA_MISION[intencion] or intencion == "progreso" then de = id and Titulo(id)
  elseif intencion == "npc_donde" then de = pnj and pnj.nombre
  elseif intencion == "zona" then de = e and e.tipo == "zona" and e.nombre or nil end
  C().Escribir(C().GRIS .. "(entendí: " .. (ETIQUETAS[intencion] or intencion) ..
    (de and (" - " .. de) or "") .. ")" .. C().FIN)

  if r.prob < 0.35 and not id and not mapa and not pnj then
    return ns.ResponderBusqueda(pregunta, true)
  end

  if intencion == "saludo" then
    Linea("¡Hola, " .. (UnitName and UnitName("player") or "aventurero") ..
      "! Pregúntame lo que quieras sobre misiones de Legion.")
  elseif intencion == "gracias" then
    Linea("¡De nada! Aquí estoy si necesitas algo más.")
  elseif intencion == "ayuda" then
    Ayuda()
  elseif intencion == "mis_misiones" then
    C().MostrarRegistro()
  elseif intencion == "progreso" then
    Progreso(id, log)
    if id then Recordar(id) end
  elseif intencion == "zona" then
    Zona(mapa, e and e.tipo == "zona" and e.nombre or nil)
  elseif intencion == "npc_donde" then
    if pnj then PnjDonde(pnj) else return ns.ResponderBusqueda(pregunta, true) end
  elseif intencion == "guia" then
    return ns.ResponderBusqueda(pregunta, true)
  elseif NECESITA_MISION[intencion] then
    if not id then
      Linea("¿De qué misión hablas? Escribe su nombre (o su número de ID).")
      for i = 1, math.min(5, #log) do Linea("   " .. C().AZUL .. "•" .. C().FIN .. " " .. log[i].titulo) end
      return
    end
    local otra = R[intencion](id, log)
    if not otra then Recordar(id) end
  end
  C().Escribir(" ")
end
