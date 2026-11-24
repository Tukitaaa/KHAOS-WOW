-- KHAOS: normalización, raíces y clasificador de intenciones (Naive Bayes entrenado).
-- Hace exactamente lo mismo que herramientas/texto_es.py; las listas de sufijos y
-- abreviaturas vienen del propio modelo entrenado (Modelo.lua), así nunca se desincronizan.
local _, ns = ...

local TILDES = {
  ["á"]="a", ["é"]="e", ["í"]="i", ["ó"]="o", ["ú"]="u", ["ü"]="u", ["ñ"]="n",
  ["Á"]="a", ["É"]="e", ["Í"]="i", ["Ó"]="o", ["Ú"]="u", ["Ü"]="u", ["Ñ"]="n",
  ["à"]="a", ["è"]="e", ["ì"]="i", ["ò"]="o", ["ù"]="u", ["ç"]="c",
}

local function SinRepetidas(p)
  -- "holaaa" -> "hola": tres o más letras iguales seguidas se quedan en una.
  local out, i, n = {}, 1, #p
  while i <= n do
    local c = p:sub(i, i)
    local j = i
    while j < n and p:sub(j + 1, j + 1) == c do j = j + 1 end
    local largo = j - i + 1
    if largo >= 3 and c:match("%a") then
      out[#out + 1] = c
    else
      out[#out + 1] = p:sub(i, j)
    end
    i = j + 1
  end
  return table.concat(out)
end

function ns.NormalizarFrase(texto)
  texto = (texto or ""):lower()
  for con, sin in pairs(TILDES) do texto = texto:gsub(con, sin) end
  texto = texto:gsub("<mision>", " xmision "):gsub("<npc>", " xnpc "):gsub("<zona>", " xzona ")
  texto = texto:gsub("[^a-z0-9 ]+", " ")
  local abreviaturas = ns.Modelo and ns.Modelo.abreviaturas or {}
  local palabras = {}
  for p in texto:gmatch("%S+") do
    p = SinRepetidas(p)
    if #p > 3 then
      -- "holaa" -> "hola": letra repetida al final.
      local ultima = p:sub(-1)
      if ultima:match("%a") then
        while #p > 1 and p:sub(-2, -2) == ultima do p = p:sub(1, -2) end
      end
    end
    local larga = abreviaturas[p]
    if larga then
      for q in larga:gmatch("%S+") do palabras[#palabras + 1] = q end
    else
      palabras[#palabras + 1] = p
    end
  end
  return palabras
end

local ESPECIALES = { xmision = true, xnpc = true, xzona = true }
local VERBO = { "ar", "er", "ir" }
local REFLEXIVO = { "", "se", "me", "te", "nos" }
local PRONOMBRE = { "", "la", "lo", "le", "las", "los", "les" }

local function Termina(p, s) return s == "" or p:sub(-#s) == s end

function ns.Raiz(p)
  if #p <= 3 or ESPECIALES[p] or p:match("^%d+$") then return p end
  -- Pronombres pegados: "entregarla" -> "entregar".
  local mejor
  for _, v in ipairs(VERBO) do
    for _, r in ipairs(REFLEXIVO) do
      for _, q in ipairs(PRONOMBRE) do
        if r .. q ~= "" then
          local suf = v .. r .. q
          if Termina(p, suf) and (not mejor or #suf > #mejor[1]) then mejor = { suf, v } end
        end
      end
    end
  end
  if mejor and #p - #mejor[1] >= 3 then
    p = p:sub(1, #p - #mejor[1]) .. mejor[2]
  end
  for _, s in ipairs(ns.Modelo and ns.Modelo.sufijos or {}) do
    if Termina(p, s) and #p - #s >= 3 then return p:sub(1, #p - #s) end
  end
  return p
end

function ns.RaicesDe(palabras)
  local r = {}
  for i, p in ipairs(palabras) do r[i] = ns.Raiz(p) end
  return r
end

function ns.Rasgos(raices)
  local out = {}
  for i, r in ipairs(raices) do out[#out + 1] = r end
  for i = 1, #raices - 1 do out[#out + 1] = raices[i] .. "_" .. raices[i + 1] end
  out[#out + 1] = "^" .. (raices[1] or "")
  return out
end

-- Si una raíz no está en el modelo, buscamos una parecida (una letra de diferencia).
local cacheParecida = {}
local function Parecida(r)
  if cacheParecida[r] ~= nil then return cacheParecida[r] or nil end
  local encontrada = false
  if #r >= 5 and ns.Distancia then
    for _, v in ipairs(ns.Modelo.vocabulario) do
      if #v >= 5 and math.abs(#v - #r) <= 1 and ns.Distancia(r, v, 1) <= 1 then
        encontrada = v
        break
      end
    end
  end
  cacheParecida[r] = encontrada
  return encontrada or nil
end

local COMUNES = {}
for p in ([[a al de del el en la las lo los un una y o que se me te le mi tu su para por con sin
  es esta este esa ese eso esto ya no si pero mas muy]]):gmatch("%S+") do COMUNES[p] = true end

-- Clasifica una lista de palabras ya normalizadas. Devuelve intención, probabilidad y
-- la lista completa ordenada { {intencion, prob}, ... }.
function ns.Clasificar(palabras)
  local M = ns.Modelo
  if not M then return nil, 0, {} end
  local raices = ns.RaicesDe(palabras)
  for i, r in ipairs(raices) do
    if not M.peso[r] and not r:find("^x") then
      local p = Parecida(r)
      if p then raices[i] = p end
    end
  end
  -- ¿Cuántas palabras con significado conoce el modelo? (0 = la pregunta es de otro tema)
  local conocidas, contenido = 0, 0
  for _, r in ipairs(raices) do
    if not COMUNES[r] then
      contenido = contenido + 1
      if M.peso[r] then conocidas = conocidas + 1 end
    end
  end
  local puntos = {}
  for c = 1, #M.intenciones do puntos[c] = M.prior[c] end
  for _, f in ipairs(ns.Rasgos(raices)) do
    local w = M.peso[f]
    if w then
      for c = 1, #M.intenciones do puntos[c] = puntos[c] + (w[c] or M.defecto[c]) end
    end
  end
  local maximo = -math.huge
  for c = 1, #puntos do if puntos[c] > maximo then maximo = puntos[c] end end
  local suma = 0
  for c = 1, #puntos do suma = suma + math.exp(puntos[c] - maximo) end
  local lista = {}
  for c = 1, #puntos do
    lista[c] = { M.intenciones[c], math.exp(puntos[c] - maximo) / suma }
  end
  table.sort(lista, function(a, b) return a[2] > b[2] end)
  return lista[1][1], lista[1][2], lista, conocidas, contenido
end
