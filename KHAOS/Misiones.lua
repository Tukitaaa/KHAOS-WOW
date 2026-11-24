-- KHAOS: búsqueda en la base completa de misiones de Legion (Misiones_*.lua).
local _, ns = ...

local WQ, SOLO_A, SOLO_H = 1, 2, 4
local indice -- palabra del título -> { questID, ... }
local vocabulario -- lista de palabras de títulos (para faltas de ortografía)

local function ConstruirIndice()
  indice, vocabulario = {}, {}
  for id, m in pairs(ns.Misiones or {}) do
    local vistas = {}
    for _, p in ipairs(ns.Palabras(m[1])) do
      if not vistas[p] then
        vistas[p] = true
        if not indice[p] then
          indice[p] = {}
          vocabulario[#vocabulario + 1] = p
        end
        local lista = indice[p]
        lista[#lista + 1] = id
      end
    end
  end
end

-- Palabras del vocabulario que se parecen a p (exacta, prefijo o una falta).
local function Parecidas(p)
  local res = {}
  if indice[p] then res[#res + 1] = { p, 1 } end
  if #p < 4 then return res end
  local tol = (#p >= 8) and 2 or 1
  for _, v in ipairs(vocabulario) do
    if v ~= p and #v >= 4 then
      if v:sub(1, #p) == p then
        res[#res + 1] = { v, 0.8 }
      elseif ns.Distancia(p, v, tol) <= tol then
        res[#res + 1] = { v, 0.6 }
      end
    end
  end
  return res
end

-- Busca misiones por su nombre. Devuelve { {id=, puntos=}, ... } ordenadas.
function ns.BuscarMisiones(pregunta, misionesLog, maximo)
  if not ns.Misiones then return {} end
  if not indice then ConstruirIndice() end

  -- ¿Han escrito un número? Puede ser el ID de la misión.
  local numero = tonumber(pregunta:match("^%s*(%d+)%s*$") or "")
  if numero and ns.Misiones[numero] then return { { id = numero, puntos = 99, cobertura = 1 } } end

  local consulta = ns.Palabras(pregunta)
  if #consulta == 0 then return {} end
  local puntos = {}
  for _, p in ipairs(consulta) do
    local mejorPorMision = {}
    for _, par in ipairs(Parecidas(p)) do
      for _, id in ipairs(indice[par[1]]) do
        if (mejorPorMision[id] or 0) < par[2] then mejorPorMision[id] = par[2] end
      end
    end
    for id, w in pairs(mejorPorMision) do puntos[id] = (puntos[id] or 0) + w end
  end

  local enLog = {}
  for _, m in ipairs(misionesLog or {}) do
    if m.questID then enLog[m.questID] = true end
  end
  local faccion = UnitFactionGroup and UnitFactionGroup("player")
  local necesario = math.max(1, math.ceil(#consulta * 0.6))

  local lista = {}
  for id, pts in pairs(puntos) do
    if pts >= necesario - 0.5 then
      local m = ns.Misiones[id]
      local largo = #ns.Palabras(m[1])
      local total = pts * 2 - 0.15 * math.max(0, largo - pts)
      if enLog[id] then total = total + 3 end
      local b = m[10] or 0
      if (faccion == "Alliance" and b % 8 >= 4) or (faccion == "Horde" and b % 4 >= 2) then
        total = total - 2
      end
      if b % 2 == 1 then total = total - 0.5 end -- misiones del mundo, un poco menos
      lista[#lista + 1] = { id = id, puntos = total, cobertura = pts / #consulta }
    end
  end
  table.sort(lista, function(a, b) return a.puntos > b.puntos end)
  local top = {}
  for i = 1, math.min(maximo or 3, #lista) do top[i] = lista[i] end
  return top
end

-- Sustituye las marcas del texto de misión ($n nombre, $c clase, $r raza, $g él:ella;).
function ns.TextoMision(texto)
  if not texto then return "" end
  local nombre = UnitName and UnitName("player") or "aventurero"
  local clase = UnitClass and UnitClass("player") or ""
  local raza = UnitRace and UnitRace("player") or ""
  local mujer = UnitSex and UnitSex("player") == 3
  texto = texto:gsub("%$[gG]%s*([^:;]*):([^;]*);", function(a, b) return mujer and b or a end)
  texto = texto:gsub("%$[nN]", nombre):gsub("%$[cC]", clase):gsub("%$[rR]", raza)
  return texto
end

local function NombreZona(mapa)
  if mapa and mapa > 0 and GetMapNameByID then
    local nombre = GetMapNameByID(mapa)
    if nombre and nombre ~= "" then return nombre end
  end
end

local function Titulo(id)
  local m = ns.Misiones and ns.Misiones[id]
  return m and m[1] or ("#" .. id)
end

-- Devuelve las líneas de texto que describen una misión de la base.
function ns.LineasMision(id, desdeLog)
  local m = ns.Misiones and ns.Misiones[id]
  if not m then return nil end
  local L = {}
  local etiquetas = {}
  if m[9] and m[9] > 0 then etiquetas[#etiquetas + 1] = "nivel " .. m[9] end
  local zona = NombreZona(m[8])
  if zona then etiquetas[#etiquetas + 1] = zona end
  local b = m[10] or 0
  if b % 2 == 1 then etiquetas[#etiquetas + 1] = "misión del mundo" end
  if b % 4 >= 2 then etiquetas[#etiquetas + 1] = "solo Alianza" end
  if b % 8 >= 4 then etiquetas[#etiquetas + 1] = "solo Horda" end
  L[#L + 1] = { "titulo", m[1] .. (#etiquetas > 0 and ("  (" .. table.concat(etiquetas, ", ") .. ")") or "") }
  if m[2] ~= "" then L[#L + 1] = { "texto", "Objetivo: " .. ns.TextoMision(m[2]) } end
  if not desdeLog then
    for _, o in ipairs(m[3]) do L[#L + 1] = { "paso", ns.TextoMision(o) } end
  end
  local da = ns.Aprendido and ns.Aprendido(id, "da")
  if da then
    L[#L + 1] = { "texto", "Te la da: " .. da }
  elseif m[4] ~= "" then
    if m[4]:sub(1, 1) == "~" then
      L[#L + 1] = { "texto", "Probablemente te la da: " .. m[4]:sub(2) }
    else
      L[#L + 1] = { "texto", "Te la da: " .. m[4] }
    end
  end
  local recibe = ns.Aprendido and ns.Aprendido(id, "recibe")
  if recibe then
    L[#L + 1] = { "texto", "Se entrega a: " .. recibe }
  elseif m[5] ~= "" then
    L[#L + 1] = { "texto", "Se entrega a: " .. m[5] }
  end

  -- Cadena: hasta 4 misiones anteriores.
  local cadena, actual, vistas = {}, m[6], {}
  while actual and actual > 0 and #cadena < 4 and not vistas[actual] do
    vistas[actual] = true
    table.insert(cadena, 1, Titulo(actual))
    actual = ns.Misiones[actual] and ns.Misiones[actual][6]
  end
  if #cadena > 0 then
    L[#L + 1] = { "texto", "Antes tienes que hacer: " .. table.concat(cadena, " > ") }
  end
  if m[7] and m[7] > 0 then L[#L + 1] = { "texto", "Después sigue con: " .. Titulo(m[7]) } end
  for _, linea in ipairs(ns.LineasPuntos(id)) do L[#L + 1] = linea end
  L[#L + 1] = { "id", "ID de la misión: " .. id }
  return L
end

-- "Dónde": puntos de la base convertidos a coordenadas del mapa si la zona está calibrada.
function ns.LineasPuntos(id)
  local L, vistos, sinCalibrar = {}, {}, {}
  for _, p in ipairs(ns.Puntos and ns.Puntos[id] or {}) do
    local mapa, tipo, X, Y = p[1], p[2], p[3], p[4]
    local zona = NombreZona(mapa) or ("mapa " .. mapa)
    local mx, my
    if ns.AMapa then mx, my = ns.AMapa(mapa, X, Y) end
    if mx then
      local clave = string.format("%d:%.0f:%.0f", mapa, mx, my)
      if not vistos[clave] then
        vistos[clave] = true
        local que = (tipo == 1) and "Entregar en: " or "Ve a: "
        L[#L + 1] = { "donde", que .. zona .. string.format(" %.1f, %.1f", mx, my) }
      end
    elseif not sinCalibrar[zona] then
      sinCalibrar[zona] = true
      L[#L + 1] = { "texto", "Zona: " .. zona .. " (camina un poco por ella para que KHAOS " ..
        "aprenda sus coordenadas)" }
    end
  end
  return L
end

-- Resumen de una línea para el aviso automático al aceptar una misión.
function ns.ResumenCorto(id)
  local m = ns.Misiones and ns.Misiones[id]
  if not m then return end
  local partes = {}
  for _, l in ipairs(ns.LineasPuntos(id)) do
    if l[1] == "donde" then partes[#partes + 1] = l[2]; break end
  end
  local recibe = ns.Aprendido and ns.Aprendido(id, "recibe")
  if recibe or m[5] ~= "" then partes[#partes + 1] = "Se entrega a: " .. (recibe or m[5]) end
  if m[7] and m[7] > 0 then partes[#partes + 1] = "Después: " .. Titulo(m[7]) end
  return m[1], table.concat(partes, " | ")
end
