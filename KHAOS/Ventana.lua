-- KHAOS: ventana tipo chat y comando /guia.
local _, ns = ...

local AMARILLO, VERDE, GRIS, AZUL = "|cffffd100", "|cff40ff40", "|cff9d9d9d", "|cff66bbff"
local FIN = "|r"

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------
local ventana

local function CrearVentana()
  local f = CreateFrame("Frame", "KhaosVentana", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(460, 380)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "KhaosVentana") -- se cierra con Escape

  f.titulo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.titulo:SetPoint("TOP", 0, -5)
  f.titulo:SetText("KHAOS - pregúntame sobre misiones")

  local salida = CreateFrame("ScrollingMessageFrame", nil, f)
  salida:SetPoint("TOPLEFT", 12, -30)
  salida:SetPoint("BOTTOMRIGHT", -12, 40)
  salida:SetFontObject(GameFontHighlightSmall)
  salida:SetJustifyH("LEFT")
  salida:SetFading(false)
  salida:SetMaxLines(500)
  salida:SetSpacing(2)
  salida:EnableMouseWheel(true)
  salida:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  f.salida = salida

  local entrada = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  entrada:SetPoint("BOTTOMLEFT", 18, 12)
  entrada:SetPoint("BOTTOMRIGHT", -12, 12)
  entrada:SetHeight(20)
  entrada:SetAutoFocus(false)
  entrada:SetScript("OnEnterPressed", function(self)
    local texto = self:GetText()
    self:SetText("")
    if texto and texto:match("%S") then ns.Responder(texto) end
  end)
  entrada:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.entrada = entrada

  f:Hide()
  return f
end

local function Escribir(texto)
  if not ventana then ventana = CrearVentana() end
  ventana.salida:AddMessage(texto)
end

local function Abrir()
  if not ventana then ventana = CrearVentana() end
  ventana:Show()
  ventana.entrada:SetFocus()
end

---------------------------------------------------------------------------
-- Respuestas
---------------------------------------------------------------------------
local function MostrarGuia(guia, mision)
  Escribir(AMARILLO .. guia.titulo .. FIN ..
    (mision and (VERDE .. "  (la tienes en el registro)" .. FIN) or ""))
  for linea in (guia.texto .. "\n"):gmatch("(.-)\n") do
    if linea:match("^%s*%-") then
      Escribir("   " .. AZUL .. "•" .. FIN .. linea:gsub("^%s*%-%s*", " "))
    elseif linea:match("%S") then
      Escribir(linea)
    end
  end
  Escribir(" ")
end

local function EscribirLineas(lineas)
  for _, l in ipairs(lineas) do
    local tipo, texto = l[1], l[2]
    if tipo == "titulo" then
      Escribir(AMARILLO .. "Misión: " .. texto .. FIN)
    elseif tipo == "paso" then
      Escribir("   " .. AZUL .. "•" .. FIN .. " " .. texto)
    elseif tipo == "donde" then
      Escribir(VERDE .. texto .. FIN)
    elseif tipo == "id" then
      Escribir(GRIS .. texto .. FIN)
    else
      Escribir(texto)
    end
  end
end

-- Misión que llevas en el registro: progreso real del juego + datos de la base.
local function MostrarMisionLog(m)
  local lineas = m.questID and ns.LineasMision and ns.LineasMision(m.questID, true)
  if lineas then
    EscribirLineas({ lineas[1] })
  else
    Escribir(AMARILLO .. "Misión: " .. m.titulo .. FIN)
  end
  if m.completada then Escribir(VERDE .. "¡Completada! Ve a entregarla." .. FIN) end
  if m.resumen and m.resumen ~= "" then Escribir(m.resumen) end
  for _, o in ipairs(m.objetivos) do
    Escribir("   " .. (o.hecho and (VERDE .. "[x] ") or (GRIS .. "[ ] ")) .. FIN .. o.texto)
  end
  if lineas then
    local resto = {}
    for i = 2, #lineas do
      if not lineas[i][2]:find("^Objetivo:") then resto[#resto + 1] = lineas[i] end
    end
    EscribirLineas(resto)
  end
  Escribir(" ")
end

local function MostrarMisionBase(id)
  local lineas = ns.LineasMision and ns.LineasMision(id)
  if lineas then EscribirLineas(lineas); Escribir(" ") end
end

function ns.ResponderBusqueda(pregunta, sinEco)
  Abrir()
  if not sinEco then Escribir(GRIS .. "> " .. pregunta .. FIN) end
  local misiones = ns.MisionesActivas()
  local mostradas = {}

  -- 1) ¿La pregunta nombra una misión que llevas? Progreso + datos de la base.
  local nombradas = ns.MisionesEnPregunta(pregunta, misiones)
  for _, m in ipairs(nombradas) do
    MostrarMisionLog(m)
    if m.questID then mostradas[m.questID] = true end
  end

  -- 2) Guías escritas (temas generales) y 3) base completa de misiones.
  local guias = ns.Buscar(pregunta, misiones, 2)
  local candidatas = ns.BuscarMisiones and ns.BuscarMisiones(pregunta, misiones, 6) or {}
  -- Si el nombre de una misión coincide entero, solo dejamos guías muy relacionadas.
  if candidatas[1] and candidatas[1].cobertura >= 1 then
    local filtradas = {}
    for _, g in ipairs(guias) do
      if g.puntos >= 8 then filtradas[#filtradas + 1] = g end
    end
    guias = filtradas
  end
  local deBase, cupo, titulos = {}, (#guias > 0) and 2 or 3, {}
  for _, m in ipairs(nombradas) do titulos[m.titulo] = true end
  for _, r in ipairs(candidatas) do
    local titulo = ns.Misiones[r.id][1]
    if not mostradas[r.id] and not titulos[titulo] and #deBase < cupo
       and (#guias == 0 or r.cobertura >= 0.8) then
      deBase[#deBase + 1] = r.id
      titulos[titulo] = true
    end
  end

  if #guias == 0 and #nombradas == 0 and #deBase == 0 then
    ns.AnotarSinRespuesta(pregunta)
    Escribir("No encuentro nada sobre eso (lo he anotado para añadirlo más adelante).")
    local sugerencias = ns.Sugerencias(pregunta, 3)
    if #sugerencias > 0 then
      Escribir("¿Quizás buscabas alguno de estos temas?")
      for _, g in ipairs(sugerencias) do Escribir("  • " .. g.titulo) end
    end
    Escribir("Consejo: escribe el nombre de la misión tal y como sale en el juego, " ..
      "o su número de ID. Ejemplo: " .. AMARILLO .. "/khaos " ..
      (misiones[1] and misiones[1].titulo or "Unir las Islas") .. FIN)
    Escribir(" ")
    return
  end
  for _, r in ipairs(guias) do MostrarGuia(r.guia, r.mision) end
  for _, id in ipairs(deBase) do MostrarMisionBase(id) end
end

local function MostrarRegistro()
  Abrir()
  local misiones = ns.MisionesActivas()
  local conGuia = ns.GuiasDelRegistro(misiones)
  Escribir(AMARILLO .. "Tu registro tiene " .. #misiones .. " misiones." .. FIN)
  if #conGuia == 0 then
    Escribir("Escribe " .. AMARILLO .. "/khaos <nombre de la misión>" .. FIN ..
      " para ver todos los detalles de una.")
  end
  for _, r in ipairs(conGuia) do MostrarGuia(r.guia, r.mision) end
  for _, m in ipairs(misiones) do
    local d = m.questID and ns.Misiones and ns.Misiones[m.questID]
    local extra = (d and d[5] ~= "") and (GRIS .. "  - se entrega a " .. d[5] .. FIN) or ""
    Escribir((m.completada and VERDE .. "[x] " or "[ ] ") .. FIN .. m.titulo .. extra)
  end
  Escribir(" ")
end

-- Herramientas de la ventana para el módulo que entiende las preguntas (Entender.lua).
ns.UI = {
  Abrir = Abrir, Escribir = Escribir, EscribirLineas = EscribirLineas,
  MostrarGuia = MostrarGuia, MostrarMisionLog = MostrarMisionLog,
  MostrarMisionBase = MostrarMisionBase, MostrarRegistro = function() MostrarRegistro() end,
  AMARILLO = AMARILLO, VERDE = VERDE, GRIS = GRIS, AZUL = AZUL, FIN = FIN,
}
ns.Responder = ns.Responder or ns.ResponderBusqueda

local function MostrarLista()
  Abrir()
  Escribir(AMARILLO .. "Temas disponibles (" .. #(ns.Guias or {}) .. "):" .. FIN)
  for _, g in ipairs(ns.Guias or {}) do Escribir("  • " .. g.titulo) end
  Escribir(" ")
end

local function MostrarAyuda()
  Abrir()
  Escribir(AMARILLO .. "KHAOS" .. FIN .. " - guía offline de Legion 7.3.5")
  Escribir("  /khaos <pregunta>   p. ej. /khaos como desbloqueo volar")
  Escribir("  /khaos misiones     guías de las misiones de tu registro")
  Escribir("  /khaos lista        todos los temas")
  Escribir("  /khaos avisos       activa o desactiva el aviso al aceptar una misión")
  Escribir("  /khaos              abre esta ventana (también vale /guia o /kh)")
  Escribir("También puedes escribir la pregunta en la caja de abajo.")
  Escribir(GRIS .. "Base: " .. ((function() local n = 0 for _ in pairs(ns.Misiones or {}) do n = n + 1 end return n end)()) ..
    " misiones. Aprendido jugando: " .. (ns.TotalAprendido and ns.TotalAprendido() or 0) ..
    " misiones. Zonas calibradas: " .. (ns.ZonasCalibradas and ns.ZonasCalibradas() or 0) .. "." .. FIN)
  Escribir(" ")
end

SLASH_KHAOS1 = "/khaos"
SLASH_KHAOS2 = "/guia"
SLASH_KHAOS3 = "/kh"
SlashCmdList["KHAOS"] = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local orden = ns.Normalizar(msg)
  if msg == "" then
    if ventana and ventana:IsShown() then ventana:Hide() else MostrarAyuda() end
  elseif orden == "misiones" or orden == "registro" then
    MostrarRegistro()
  elseif orden == "lista" or orden == "temas" then
    MostrarLista()
  elseif orden == "avisos" then
    KhaosDB = KhaosDB or {}
    KhaosDB.sinAvisos = not KhaosDB.sinAvisos
    print("|cffff3030KHAOS|r: avisos al aceptar misiones " ..
      (KhaosDB.sinAvisos and "desactivados." or "activados."))
  elseif orden == "ayuda" or orden == "help" then
    MostrarAyuda()
  else
    ns.Responder(msg)
  end
end

-- Aviso automático en el chat al aceptar una misión.
local avisos = CreateFrame("Frame")
avisos:RegisterEvent("QUEST_ACCEPTED")
avisos:SetScript("OnEvent", function(_, _, indice, questID)
  if not questID and indice and GetQuestLogTitle then
    questID = select(8, GetQuestLogTitle(indice))
  end
  if questID then
    KhaosDB = KhaosDB or {}
    KhaosDB.ultimaAceptada = questID
    ns.ultimaAceptadaHora = GetTime and GetTime() or 0
  end
  if KhaosDB and KhaosDB.sinAvisos then return end
  if not questID or not ns.ResumenCorto then return end
  local titulo, resumen = ns.ResumenCorto(questID)
  if not titulo then return end
  local texto = "|cffff3030KHAOS|r: " .. AMARILLO .. titulo .. FIN
  if resumen and resumen ~= "" then texto = texto .. " - " .. resumen end
  print(texto .. GRIS .. "  (/khaos " .. questID .. " para más)" .. FIN)
end)
