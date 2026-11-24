-- KHAOS se calibra solo: mientras caminas, compara tu posición en el mundo (UnitPosition)
-- con tu posición en el mapa (GetPlayerMapPosition). Con dos o más puntos separados de una
-- zona ya sabe convertir las coordenadas de la base de datos en "45.2, 61.9" de ese mapa.
-- Se guarda en KhaosDB.calibracion y vale para todos tus personajes.
local _, ns = ...

local MAX_MUESTRAS = 12
local cada = 2 -- segundos entre muestras

local function Muestras(mapa)
  KhaosDB = KhaosDB or {}
  KhaosDB.calibracion = KhaosDB.calibracion or {}
  local c = KhaosDB.calibracion[mapa]
  if not c then
    c = { muestras = {} }
    KhaosDB.calibracion[mapa] = c
  end
  return c
end

-- Recta por mínimos cuadrados: y = a*x + b. Devuelve a, b y r² (calidad del ajuste).
local function Recta(xs, ys)
  local n = #xs
  if n < 2 then return end
  local sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0
  for i = 1, n do
    local x, y = xs[i], ys[i]
    sx, sy = sx + x, sy + y
    sxx, syy, sxy = sxx + x * x, syy + y * y, sxy + x * y
  end
  local vx = n * sxx - sx * sx
  local vy = n * syy - sy * sy
  if vx <= 0 or vy <= 0 then return end
  local a = (n * sxy - sx * sy) / vx
  local b = (sy - a * sx) / n
  local r2 = (n * sxy - sx * sy) ^ 2 / (vx * vy)
  return a, b, r2
end

-- Calcula la conversión de una zona. Probamos qué componente de UnitPosition corresponde a
-- cada eje del mapa (así no dependemos de suposiciones sobre el orden de los valores).
local function Ajustar(c)
  local m = c.muestras
  if #m < 3 then return end
  local u1, u2, mx, my = {}, {}, {}, {}
  for i, s in ipairs(m) do u1[i], u2[i], mx[i], my[i] = s[1], s[2], s[3], s[4] end
  local function Mejor(objetivo)
    local a1, b1, r1 = Recta(u1, objetivo)
    local a2, b2, r2 = Recta(u2, objetivo)
    if (r1 or 0) >= (r2 or 0) then return 1, a1, b1, r1 or 0 end
    return 2, a2, b2, r2 or 0
  end
  -- Si solo has caminado en línea recta no se puede distinguir un eje del otro.
  local _, _, recta = Recta(u1, u2)
  if recta and recta > 0.9 then return end
  local ix, ax, bx, rx = Mejor(mx)
  local iy, ay, by, ry = Mejor(my)
  if ix ~= iy and rx > 0.995 and ry > 0.995 then
    c.ajuste = { ix = ix, ax = ax, bx = bx, iy = iy, ay = ay, by = by }
  end
end

local ultimo = 0
local marco = CreateFrame("Frame")
marco:SetScript("OnUpdate", function(_, transcurrido)
  ultimo = ultimo + transcurrido
  if ultimo < cada then return end
  ultimo = 0
  if not UnitPosition or not GetPlayerMapPosition then return end
  if WorldMapFrame and WorldMapFrame:IsShown() then return end
  if IsInInstance and IsInInstance() then return end
  if SetMapToCurrentZone then SetMapToCurrentZone() end
  local mapa = GetCurrentMapAreaID and GetCurrentMapAreaID()
  local px, py = GetPlayerMapPosition("player")
  local u1, u2 = UnitPosition("player")
  if not mapa or not px or not u1 or (px == 0 and py == 0) then return end

  local c = Muestras(mapa)
  local m = c.muestras
  -- Solo guardamos puntos alejados (más de 40 metros) de los que ya tenemos.
  for _, s in ipairs(m) do
    if (s[1] - u1) ^ 2 + (s[2] - u2) ^ 2 < 1600 then return end
  end
  if #m >= MAX_MUESTRAS then table.remove(m, 1) end
  m[#m + 1] = { u1, u2, px * 100, py * 100 }
  Ajustar(c)
end)

-- Convierte un punto de la base (X norte, Y oeste) en coordenadas del mapa, o nil.
-- Las coordenadas de la base son las del servidor: X = norte, Y = oeste. UnitPosition
-- devuelve las mismas dos, y el ajuste ya sabe cuál va con cada eje del mapa.
function ns.AMapa(mapa, X, Y)
  local c = KhaosDB and KhaosDB.calibracion and KhaosDB.calibracion[mapa]
  local f = c and c.ajuste
  if not f then return end
  -- El eje horizontal del mapa va con la coordenada "oeste" (Y); el vertical, con "norte" (X).
  -- Elegimos cuál de las dos de UnitPosition es cuál por la pendiente que aprendimos.
  local valores = {}
  valores[f.ix] = Y
  valores[f.iy] = X
  local mx = f.ax * valores[f.ix] + f.bx
  local my = f.ay * valores[f.iy] + f.by
  if mx < -5 or mx > 105 or my < -5 or my > 105 then return end
  return mx, my
end

function ns.ZonasCalibradas()
  local n = 0
  for _, c in pairs(KhaosDB and KhaosDB.calibracion or {}) do
    if c.ajuste then n = n + 1 end
  end
  return n
end
