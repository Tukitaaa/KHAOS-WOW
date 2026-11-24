-- KHAOS aprende jugando: cada vez que un personaje te ofrece o te recoge una misión,
-- guarda quién era y dónde estaba (zona y coordenadas). Así rellena lo que la base no trae.
-- Se guarda en KhaosDB.aprendido (SavedVariables), compartido entre tus personajes.
local _, ns = ...

local function Posicion()
  if not GetPlayerMapPosition then return end
  -- Si el mapa del mundo está abierto en otra zona no movemos lo que mira el jugador.
  if WorldMapFrame and WorldMapFrame:IsShown() then return end
  if SetMapToCurrentZone then SetMapToCurrentZone() end
  local mapa = GetCurrentMapAreaID and GetCurrentMapAreaID()
  local x, y = GetPlayerMapPosition("player")
  if x and y and (x > 0 or y > 0) then
    return mapa, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
  end
  return mapa
end

local function QuienEs()
  local nombre = UnitName("questnpc") or UnitName("npc")
  if nombre and nombre ~= "" then return nombre end
end

local function Guardar(tipo)
  local id = GetQuestID and GetQuestID()
  if not id or id == 0 then return end
  KhaosDB = KhaosDB or {}
  KhaosDB.aprendido = KhaosDB.aprendido or {}
  local registro = KhaosDB.aprendido[id] or {}
  local mapa, x, y = Posicion()
  registro[tipo] = { QuienEs() or "", mapa or 0, x or 0, y or 0 }
  KhaosDB.aprendido[id] = registro
end

local eventos = CreateFrame("Frame")
eventos:RegisterEvent("QUEST_DETAIL")   -- te ofrecen la misión
eventos:RegisterEvent("QUEST_COMPLETE") -- vas a entregarla
eventos:SetScript("OnEvent", function(_, evento)
  if evento == "QUEST_DETAIL" then Guardar("da") else Guardar("recibe") end
end)

-- Texto "Nombre (Zona 45.2, 61.0)" a partir de lo aprendido.
function ns.Aprendido(id, tipo)
  local r = KhaosDB and KhaosDB.aprendido and KhaosDB.aprendido[id]
  r = r and r[tipo]
  if not r then return end
  local nombre, mapa, x, y = r[1], r[2], r[3], r[4]
  local donde = {}
  local zona = mapa and mapa > 0 and GetMapNameByID and GetMapNameByID(mapa)
  if zona then donde[#donde + 1] = zona end
  if x and x > 0 then donde[#donde + 1] = string.format("%.1f, %.1f", x, y) end
  local texto = (nombre ~= "" and nombre) or "?"
  if #donde > 0 then texto = texto .. " (" .. table.concat(donde, " ") .. ")" end
  return texto
end

function ns.TotalAprendido()
  local n = 0
  for _ in pairs(KhaosDB and KhaosDB.aprendido or {}) do n = n + 1 end
  return n
end
