local addon = CreateFrame("Frame", "RaidPointsManagerEventFrame")
local db, window, scroll, refresh, roundLabel
local rows, names, groups = {}, {}, {}
local sortMode = "GROUP"
local activeTab = "RAID"
local tabButtons = {}
local manualControls = {}
local appearanceControls = {}
local settingsPanel, backgroundTexture
local lastRosterTab = "RAID"
local backgroundOptions = {
    {name="Black", color={0.025,0.025,0.035}},
    {name="Slate", color={0.12,0.14,0.18}},
    {name="Navy", color={0.035,0.075,0.20}},
    {name="Burgundy", color={0.24,0.045,0.055}},
    {name="Forest", color={0.055,0.17,0.095}},
    {name="Brown", color={0.23,0.12,0.055}},
    {name="Parchment", file="Parchment"},
    {name="Dark Scroll", file="DarkParchment"},
    {name="Wooden Table", file="Wood"},
    {name="War Table", file="WarTable"},
}
local fontOptions = {
    {name="Friz Quadrata", path="Fonts\\FRIZQT__.TTF"},
    {name="Arial Narrow", path="Fonts\\ARIALN.TTF"},
    {name="Morpheus", path="Fonts\\MORPHEUS.TTF"},
    {name="Skurri", path="Fonts\\SKURRI.TTF"},
}
local fontTargets = {}
local function applyAppearance()
    if not db or not window or not backgroundTexture then return end
    local option = backgroundOptions[db.backgroundIndex] or backgroundOptions[1]
    if option.file then
        backgroundTexture:SetTexture("Interface\\AddOns\\RaidPointsManager\\Textures\\" .. option.file)
        backgroundTexture:SetVertexColor(1,1,1,1)
    else
        backgroundTexture:SetTexture(1,1,1,1)
        backgroundTexture:SetVertexColor(option.color[1],option.color[2],option.color[3],1)
    end
    backgroundTexture:SetAlpha((db.backgroundOpacity or 85)/100)
    local font = fontOptions[db.fontIndex] or fontOptions[1]
    for _, item in ipairs(fontTargets) do
        local target, size = item[1], item[2]
        if target and target.SetFont then target:SetFont(font.path, size, "OUTLINE") end
    end
end
local function showWhen(frame, visible)
    if visible then frame:Show() else frame:Hide() end
end
local function trackFont(target, size)
    fontTargets[#fontTargets+1]={target,size}
end

local function msg(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRaid Points:|r " .. s) end
local function ensure(name)
    if not name then return end
    if type(db.points[name]) ~= "number" then db.points[name] = 0 end
    if type(db.history[name]) ~= "table" then db.history[name] = {} end
    if type(db.roundCounts[name]) ~= "number" then db.roundCounts[name] = math.max(0, db.round - 1) end
end
local function roster()
    local found = {}
    groups = {}
    local n = GetNumRaidMembers()
    if activeTab == "MANUAL" then
        for name, included in pairs(db.manualPlayers) do
            if included then
                found[name] = true
                local g = tonumber(db.manualGroups[name])
                if g and g >= 1 and g <= 8 and g == math.floor(g) then groups[name] = g end
            end
        end
        n = -1
    end
    if n == -1 then
        -- Manual roster is not populated from the raid or party.
    elseif n > 0 then
        for i=1,n do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name then found[name] = true; groups[name] = subgroup end
        end
    else
        local me = UnitName("player")
        if me then found[me] = true; groups[me] = 1 end
        for i=1,GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then found[name] = true; groups[name] = 1 end
        end
    end
    names = {}
    for name in pairs(found) do names[#names+1] = name; ensure(name) end
    table.sort(names, function(a,b)
        if sortMode == "POINTS" then
            local pa, pb = db.points[a] or 0, db.points[b] or 0
            if pa ~= pb then return pa > pb end
        elseif sortMode == "ROUNDS" then
            local ra, rb = db.roundCounts[a] or 0, db.roundCounts[b] or 0
            if ra ~= rb then return ra > rb end
        elseif sortMode == "GROUP" then
            local ga, gb = groups[a] or 9, groups[b] or 9
            if ga ~= gb then return ga < gb end
        end
        return string.lower(a) < string.lower(b)
    end)
end
local function button(parent, text, width, x, y, click)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(25)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text); b:SetScript("OnClick", click)
    return b
end
local function clearAmountInputs()
    if not rows then return end
    for _, row in ipairs(rows) do
        if row.amount then row.amount:SetText(""); row.amount:ClearFocus() end
    end
end
local function nextRound()
    -- Every member of the current roster completes one round, even with no selection.
    roster()
    for _, name in ipairs(names) do
        ensure(name)
        db.roundCounts[name] = db.roundCounts[name] + 1
    end
    -- Commit selected scores once, including explicit zero scores.
    for name, score in pairs(db.current) do
        ensure(name)
        db.points[name] = db.points[name] + score
        db.history[name][db.round] = score
    end
    db.current = {}
    clearAmountInputs()
    db.round = db.round + 1
    roster(); refresh()
    msg("Round " .. db.round .. ".")
end
local function announce(channel)
    if channel == "RAID" and GetNumRaidMembers() == 0 then
        msg("You must be in a raid to announce to raid chat."); return
    end
    roster()
    if #names == 0 then msg("No players to announce."); return end
    -- One message per player keeps each line under the 255-character chat limit.
    SendChatMessage("Raid points - completed rounds: " .. (db.round - 1), channel)
    for _, name in ipairs(names) do
        local group = groups[name]
        local prefix = group and ("[G" .. group .. "] ") or ""
        SendChatMessage(prefix .. name .. ": " .. (db.points[name] or 0), channel)
    end
end
local function build()
    window = CreateFrame("Frame", "RaidPointsManagerWindow", UIParent)
    window:SetWidth(930); window:SetHeight(595)
    window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG")
    window:SetMovable(true); window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetClampedToScreen(true)
    window:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=10,right=10,top=10,bottom=10}})
    window:SetBackdropColor(0, 0, 0, 0)
    backgroundTexture = window:CreateTexture(nil, "BACKGROUND")
    backgroundTexture:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -12)
    backgroundTexture:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 12)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18); title:SetText("Raid Points Manager"); trackFont(title, 17)
    window:SetScript("OnHide", function() clearAmountInputs() end)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    roundLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    roundLabel:SetPoint("TOP", 0, -44)
    local function switchTab(tab)
        if tab ~= "SETTINGS" then lastRosterTab=tab end
        activeTab = tab
        if tab ~= "SETTINGS" then FauxScrollFrame_SetOffset(scroll, 0) end
        roster(); refresh()
    end
    tabButtons.raid = button(window, "Raid Roster", 130, 22, -68, function() switchTab("RAID") end)
    tabButtons.manual = button(window, "Manual Roster", 140, 158, -68, function() switchTab("MANUAL") end)
    -- Explicit, visible Settings launcher: icon texture exists in the 3.3.5 client.
    local gear = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    gear:SetWidth(116); gear:SetHeight(28)
    gear:SetPoint("TOPRIGHT", window, "TOPRIGHT", -43, -62)
    gear:SetText("Settings")
    local gearIcon = gear:CreateTexture(nil, "ARTWORK")
    gearIcon:SetWidth(19); gearIcon:SetHeight(19)
    gearIcon:SetPoint("LEFT", gear, "LEFT", 7, 0)
    gearIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
    gear:GetFontString():ClearAllPoints()
    gear:GetFontString():SetPoint("CENTER", gear, "CENTER", 10, 0)
    gear:SetScript("OnClick", function() switchTab(activeTab == "SETTINGS" and lastRosterTab or "SETTINGS") end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Appearance Settings"); GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local tabHighlights = {}
    for key, tab in pairs(tabButtons) do
        local glow = tab:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("TOPLEFT", tab, "TOPLEFT", 3, -3)
        glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 3)
        glow:SetTexture(1, 0.73, 0.12, 0.22)
        glow:Hide()
        tabHighlights[key] = glow
    end
    settingsPanel = CreateFrame("Frame", nil, window)
    settingsPanel:SetPoint("TOPLEFT", 24, -110)
    settingsPanel:SetWidth(875); settingsPanel:SetHeight(435)
    local settingsTitle = settingsPanel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    settingsTitle:SetPoint("TOPLEFT", 10, -8); settingsTitle:SetText("Appearance Settings")
    trackFont(settingsTitle, 17)
    local opacityLabel = settingsPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    opacityLabel:SetPoint("TOPLEFT", 12, -55)
    opacityLabel:SetText("Background opacity")
    local slider = CreateFrame("Slider", "RaidPointsOpacitySlider", settingsPanel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, -87); slider:SetWidth(280); slider:SetMinMaxValues(0,100); slider:SetValueStep(5)
    _G[slider:GetName().."Low"]:SetText("0%")
    _G[slider:GetName().."High"]:SetText("100%")
    _G[slider:GetName().."Text"]:SetText("")
    local opacityValue = settingsPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    opacityValue:SetPoint("LEFT", slider, "RIGHT", 15, 0)
    slider:SetScript("OnValueChanged", function(self, val)
        val=math.floor(val/5+0.5)*5
        if not db then return end
        db.backgroundOpacity=val; opacityValue:SetText(val.."%"); applyAppearance()
    end)
    appearanceControls.slider=slider
    local bgLabel = settingsPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    bgLabel:SetPoint("TOPLEFT", 12, -145); bgLabel:SetText("Background themes (click to preview and apply)")
    local bgButtons={}
    for i,opt in ipairs(backgroundOptions) do
        local b=CreateFrame("Button",nil,settingsPanel,"UIPanelButtonTemplate")
        b:SetWidth(132); b:SetHeight(31)
        local col=(i-1)%4; local r=math.floor((i-1)/4)
        b:SetPoint("TOPLEFT", 12+col*145, -172-r*42)
        b:SetText(opt.name)
        b:SetScript("OnClick", function() db.backgroundIndex=i; applyAppearance()
            for k,btn in ipairs(bgButtons) do if k==i then btn:LockHighlight() else btn:UnlockHighlight() end end
        end)
        bgButtons[i]=b
    end
    appearanceControls.bgButtons=bgButtons
    local fontLabel=settingsPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", 12, -319); fontLabel:SetText("Font (click to change)")
    local fontButtons={}
    for i,opt in ipairs(fontOptions) do
        local b=CreateFrame("Button",nil,settingsPanel,"UIPanelButtonTemplate")
        b:SetWidth(140); b:SetHeight(27); b:SetPoint("TOPLEFT", 12+(i-1)*148, -345)
        b:SetText(opt.name)
        b:SetScript("OnClick",function() db.fontIndex=i; applyAppearance()
            for k,btn in ipairs(fontButtons) do if k==i then btn:LockHighlight() else btn:UnlockHighlight() end end
        end)
        fontButtons[i]=b
    end
    appearanceControls.fontButtons=fontButtons
    local preview=settingsPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    preview:SetPoint("TOPLEFT", 12, -387); preview:SetText("Raid Points Manager  •  G1  •  125 points")
    trackFont(preview, 15)
    appearanceControls.back=button(settingsPanel,"Back to Roster",155,680,-380,function() switchTab(lastRosterTab) end)
    local manualName = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    manualName:SetWidth(155); manualName:SetHeight(24)
    manualName:SetPoint("TOPLEFT", 320, -69)
    manualName:SetAutoFocus(false); manualName:SetMaxLetters(50)
    manualName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function addManual(name)
        name = name and name:match("^%s*(.-)%s*$")
        if not name or name == "" or not name:match("^[%a][%a%-]*$") then
            msg("Enter a valid character name (letters and hyphens only)."); return
        end
        if db.manualPlayers[name] then msg(name .. " is already on the manual roster."); return end
        db.manualPlayers[name] = true
        ensure(name)
        manualName:SetText("")
        roster(); refresh()
        msg(name .. " added to manual roster.")
    end
    manualName:SetScript("OnEnterPressed", function(self) addManual(self:GetText()); self:ClearFocus() end)
    manualControls.name = manualName
    manualControls.add = button(window, "Add Name", 95, 487, -68, function() addManual(manualName:GetText()) end)
    manualControls.target = button(window, "Add Target", 105, 590, -68, function()
        if not UnitExists("target") or not UnitIsPlayer("target") then
            msg("Select a player as your target first."); return
        end
        addManual(UnitName("target"))
    end)
    -- Individual column labels share the same offsets as the row controls.
    local head = CreateFrame("Frame", nil, window)
    head:SetPoint("TOPLEFT", 25, -129)
    head:SetWidth(865); head:SetHeight(18)
    local function columnLabel(label, x, width)
        local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", head, "LEFT", x, 0)
        fs:SetWidth(width); fs:SetJustifyH("CENTER")
        fs:SetText(label)
        return fs
    end
    columnLabel("Player", 0, 125)
    columnLabel("Group", 128, 43)
    columnLabel("Round", 174, 43)
    columnLabel("Total", 221, 55)
    columnLabel("Award points", 281, 170)
    columnLabel("Custom amount / adjustment", 461, 245)
    columnLabel("Reset", 721, 70)
    columnLabel("Delete", 794, 65)
    local rosterButtons={}
    rosterButtons[#rosterButtons+1]=button(window, "Group", 85, 22, -151, function() sortMode="GROUP"; roster(); refresh() end)
    rosterButtons[#rosterButtons+1]=button(window, "Name A-Z", 95, 113, -151, function() sortMode="NAME"; roster(); refresh() end)
    rosterButtons[#rosterButtons+1]=button(window, "Points", 85, 214, -151, function() sortMode="POINTS"; roster(); refresh() end)
    rosterButtons[#rosterButtons+1]=button(window, "Rounds", 85, 305, -151, function() sortMode="ROUNDS"; roster(); refresh() end)
    local sortHint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sortHint:SetPoint("LEFT", window, "TOPLEFT", 405, -163)
    sortHint:SetText("Sort: Group / Name / Points / Rounds  |  Manual: click G to change, right-click to clear")
    scroll = CreateFrame("ScrollFrame", "RaidPointsManagerScroll", window, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -185); scroll:SetWidth(860); scroll:SetHeight(275)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 25, refresh)
    end)
    for i=1,11 do
        local row = CreateFrame("Frame", nil, window)
        row:SetWidth(860); row:SetHeight(25)
        row:SetPoint("TOPLEFT", 25, -187-(i-1)*25)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetTexture(0.025, 0.025, 0.035, (i % 2 == 0) and 0.84 or 0.74)
        local line = row:CreateTexture(nil, "BORDER")
        line:SetHeight(1); line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        line:SetTexture(0.72, 0.60, 0.35, 0.32)
        for _, x in ipairs({127, 171, 218, 280, 457, 535, 716, 794}) do
            local divider = row:CreateTexture(nil, "BORDER")
            divider:SetWidth(1)
            divider:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
            divider:SetTexture(0.72, 0.60, 0.35, 0.23)
        end
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 0, 0); row.name:SetWidth(125); row.name:SetJustifyH("LEFT"); trackFont(row.name, 11)
        row.group = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.group:SetPoint("LEFT", 130, 0); row.group:SetWidth(38); trackFont(row.group, 11)
        row.manualGroup = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.manualGroup:SetWidth(43); row.manualGroup:SetHeight(21)
        row.manualGroup:SetPoint("LEFT", 128, 0)
        row.manualGroup:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.manualGroup:SetScript("OnClick", function(self, mouseButton)
            local name = row.playerName
            if not name or activeTab ~= "MANUAL" then return end
            if mouseButton == "RightButton" then
                db.manualGroups[name] = nil
            else
                local old = tonumber(db.manualGroups[name]) or 0
                db.manualGroups[name] = (old % 8) + 1
            end
            roster(); refresh()
        end)
        row.manualGroup:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Manual group")
            GameTooltip:AddLine("Left-click: cycle G1 through G8", 1, 1, 1)
            GameTooltip:AddLine("Right-click: clear group", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.manualGroup:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.current = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.current:SetPoint("LEFT", 174, 0); row.current:SetWidth(43); trackFont(row.current, 12)
        row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.total:SetPoint("LEFT", 221, 0); row.total:SetWidth(55); trackFont(row.total, 12)
        row.total:SetTextColor(1, 0.88, 0.28, 1)
        row.buttons = {}
        for j=0,3 do
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetWidth(41); b:SetHeight(22)
            b:SetPoint("LEFT", 283+j*43, 0)
            b:SetText(j == 0 and "0" or "+"..j)
            -- Use a dedicated selection indicator rather than LockHighlight:
            -- UIPanelButtonTemplate's hover highlight can remain visible after
            -- UnlockHighlight on the 3.3.5a client.
            local indicator = b:CreateTexture(nil, "OVERLAY")
            indicator:SetTexture("Interface\\Buttons\\WHITE8X8")
            indicator:SetVertexColor(1, 0.76, 0.12, 0.34)
            indicator:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -4)
            indicator:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 4)
            indicator:Hide()
            b.selectionIndicator = indicator
            b:SetScript("OnClick", function(self)
                if row.playerName then
                    -- Clicking the already selected score cancels the pending
                    -- award for this player; no score is committed until Next Round.
                    if db.current[row.playerName] == j then
                        db.current[row.playerName] = nil
                    else
                        db.current[row.playerName] = j
                    end
                    row.amount:SetText(""); row.amount:ClearFocus()
                    refresh()
                    -- Remove any lingering mouse-hover glow after cancellation.
                    if db.current[row.playerName] == nil then
                        self:UnlockHighlight()
                        self:SetButtonState("NORMAL")
                    end
                end
            end)
            row.buttons[j+1] = b
        end
        -- A plain EditBox avoids InputBoxTemplate's large black left/right
        -- texture caps, which overlap narrow fields in the 3.3.5a client.
        local amountBorder = CreateFrame("Frame", nil, row)
        amountBorder:SetWidth(57); amountBorder:SetHeight(19)
        amountBorder:SetPoint("LEFT", row, "LEFT", 467, 0)
        amountBorder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 9,
            insets = {left = 2, right = 2, top = 2, bottom = 2}
        })
        amountBorder:SetBackdropColor(0.02, 0.02, 0.03, 0.92)
        amountBorder:SetBackdropBorderColor(0.65, 0.54, 0.32, 0.85)
        amountBorder:SetFrameLevel(row:GetFrameLevel() + 2)
        row.amount = CreateFrame("EditBox", nil, amountBorder)
        row.amount:SetPoint("TOPLEFT", amountBorder, "TOPLEFT", 5, -2)
        row.amount:SetPoint("BOTTOMRIGHT", amountBorder, "BOTTOMRIGHT", -5, 2)
        row.amount:SetFrameLevel(amountBorder:GetFrameLevel() + 1)
        row.amount:SetFontObject("GameFontHighlightSmall")
        row.amount:SetTextColor(1, 1, 1, 1)
        row.amount:SetJustifyH("LEFT")
        row.amount:SetAutoFocus(false)
        row.amount:SetNumeric(true)
        row.amount:SetMaxLetters(8)
        row.amount:SetText("")
        row.amount:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        row.amount:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        local function adjust(sign)
            local name = row.playerName
            if not name then return end
            local value = tonumber(row.amount:GetText())
            if not value or value < 1 or value > 99999999 or value ~= math.floor(value) then
                msg("Enter a whole number between 1 and 99999999.")
                return
            end
            ensure(name)
            db.points[name] = db.points[name] + sign * value
            -- Adjustments change the total, not the round history or round counter.
            row.amount:SetText(""); row.amount:ClearFocus()
            roster(); refresh()
        end
        local add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        add:SetWidth(73); add:SetHeight(22)
        add:SetPoint("LEFT", 541, 0)
        add:SetText("+ Add")
        add:SetScript("OnClick", function() adjust(1) end)
        local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        remove:SetWidth(85); remove:SetHeight(22)
        remove:SetPoint("LEFT", 620, 0)
        remove:SetText("- Remove")
        remove:SetScript("OnClick", function() adjust(-1) end)
        local reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        reset:SetWidth(70); reset:SetHeight(22)
        reset:SetPoint("LEFT", 723, 0)
        reset:SetText("Reset")
        reset:SetScript("OnClick", function()
            if row.playerName then
                StaticPopup_Show("RAID_POINTS_RESET_PLAYER", nil, nil, row.playerName)
            end
        end)
        row.removeManual = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.removeManual:SetWidth(62); row.removeManual:SetHeight(22)
        row.removeManual:SetPoint("LEFT", 794, 0)
        row.removeManual:SetText("Delete")
        row.removeManual:SetScript("OnClick", function()
            if row.playerName then
                StaticPopup_Show("RAID_POINTS_REMOVE_MANUAL", nil, nil, row.playerName)
            end
        end)
        row.reset = reset
        rows[i] = row
    end
    rosterButtons[#rosterButtons+1]=button(window, "Next Round", 150, 20, -475, function()
        StaticPopup_Show("RAID_POINTS_NEXT_ROUND")
    end)
    rosterButtons[#rosterButtons+1]=button(window, "Announce /raid", 130, 180, -475, function() announce("RAID") end)
    rosterButtons[#rosterButtons+1]=button(window, "Reset All", 115, 330, -475, function() StaticPopup_Show("RAID_POINTS_RESET_ALL") end)
    rosterButtons[#rosterButtons+1]=button(window, "Refresh Roster", 140, 20, -510, function() roster(); refresh() end)
    rosterButtons[#rosterButtons+1]=button(window, "Announce /y", 125, 180, -510, function() announce("YELL") end)
    rosterButtons[#rosterButtons+1]=button(window, "Announce /s", 125, 325, -510, function() announce("SAY") end)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 20)
    hint:SetText("/rp - toggle | Next Round counts every listed player | Custom adjustments apply immediately")
    refresh = function()
        local inSettings = activeTab == "SETTINGS"
        showWhen(settingsPanel, inSettings)
        showWhen(scroll, not inSettings)
        showWhen(head, not inSettings)
        showWhen(sortHint, not inSettings)
        showWhen(hint, not inSettings)
        for _, b in ipairs(rosterButtons) do showWhen(b, not inSettings) end
        for _, row in ipairs(rows) do if inSettings then row:Hide() end end
        for _, child in ipairs(appearanceControls.bgButtons) do
            if db.backgroundIndex == _ then child:LockHighlight() else child:UnlockHighlight() end
        end
        for i, child in ipairs(appearanceControls.fontButtons) do
            if db.fontIndex == i then child:LockHighlight() else child:UnlockHighlight() end
        end
        if inSettings then appearanceControls.slider:SetValue(db.backgroundOpacity) end
        roundLabel:SetText("Round " .. db.round .. "  |  Completed: " .. (db.round-1) .. "  |  " .. (activeTab == "RAID" and "Raid Roster" or activeTab == "MANUAL" and "Manual Roster" or "Settings"))
        for _, control in pairs(manualControls) do
            if activeTab == "MANUAL" then control:Show() else control:Hide() end
        end
        -- Keep both tabs clickable; indicate selection with a persistent gold overlay.
        tabButtons.raid:Enable()
        tabButtons.manual:Enable()
        showWhen(tabHighlights.raid, activeTab == "RAID")
        showWhen(tabHighlights.manual, activeTab == "MANUAL")
        if activeTab == "SETTINGS" then gear:LockHighlight() else gear:UnlockHighlight() end
        if inSettings then return end
        FauxScrollFrame_Update(scroll, #names, #rows, 25)
        local offset = FauxScrollFrame_GetOffset(scroll)
        for i,row in ipairs(rows) do
            local name = names[i+offset]
            if row.playerName ~= name then row.amount:SetText(""); row.amount:ClearFocus() end
            row.playerName = name
            if name then
                row.name:SetText(name)
                if activeTab == "MANUAL" then row.removeManual:Show() else row.removeManual:Hide() end
                if activeTab == "MANUAL" then
                    row.group:Hide()
                    row.manualGroup:SetText(groups[name] and ("G" .. groups[name]) or "-")
                    row.manualGroup:Show()
                else
                    row.manualGroup:Hide()
                    row.group:SetText(groups[name] and ("G" .. groups[name]) or "-")
                    row.group:Show()
                end
                local score = db.current[name]
                row.current:SetText(tostring(db.roundCounts[name] or 0))
                row.total:SetText(tostring(db.points[name] or 0))
                for j,b in ipairs(row.buttons) do
                    b:UnlockHighlight()
                    if score == j-1 then
                        b.selectionIndicator:Show()
                    else
                        b.selectionIndicator:Hide()
                    end
                end
                if not inSettings then row:Show() end
            else row:Hide() end
        end
    end
end

-- Movable minimap launcher (left-click to toggle, right-click to hide/show icon).
local minimapButton
local function updateMinimapPosition()
    if not minimapButton or not db then return end
    local angle = math.rad(db.minimapAngle or 225)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end
local function toggleWindow()
    if not window then return end
    if window:IsShown() then window:Hide() else roster(); refresh(); window:Show() end
end
local function createMinimapButton()
    minimapButton = CreateFrame("Button", "RaidPointsManagerMinimapButton", Minimap)
    minimapButton:SetWidth(32); minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\AddOns\\RaidPointsManager\\Textures\\MinimapIcon")
    minimapButton.icon = icon
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetWidth(54); border:SetHeight(54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then toggleWindow()
        elseif mouseButton == "RightButton" then
            db.minimapHidden = true
            self:Hide()
            msg("Minimap icon hidden. Type /rp icon to show it again.")
        end
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            x, y = x / scale, y / scale
            local mx, my = Minimap:GetCenter()
            db.minimapAngle = math.deg(math.atan2(y - my, x - mx))
            updateMinimapPosition()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Raid Points Manager")
        GameTooltip:AddLine("Left-click: Open / Close", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move icon", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Hide icon", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updateMinimapPosition()
    if db.minimapHidden then minimapButton:Hide() else minimapButton:Show() end
end

StaticPopupDialogs["RAID_POINTS_REMOVE_MANUAL"] = {
    text="Remove this player from the manual roster? Their points and history will be kept.",
    button1=YES, button2=NO,
    OnAccept=function(self, playerName)
        if type(playerName) ~= "string" or not db then return end
        db.manualPlayers[playerName] = nil
        roster(); refresh()
        msg(playerName .. " removed from manual roster.")
    end,
    timeout=0, whileDead=1, hideOnEscape=1, preferredIndex=3
}
StaticPopupDialogs["RAID_POINTS_NEXT_ROUND"] = {
    text="Finish this round and save the selected scores?",
    button1=YES, button2=NO, OnAccept=function() nextRound() end,
    timeout=0, whileDead=1, hideOnEscape=1, preferredIndex=3
}
StaticPopupDialogs["RAID_POINTS_RESET_PLAYER"] = {
    text="Reset all points and history for this player? This cannot be undone.",
    button1=YES, button2=NO,
    OnAccept=function(self, playerName)
        if type(playerName) ~= "string" or not db then return end
        db.points[playerName] = 0
        db.history[playerName] = {}
        db.roundCounts[playerName] = 0
        db.current[playerName] = nil
        refresh()
        msg("Points for " .. playerName .. " have been reset.")
    end,
    timeout=0, whileDead=1, hideOnEscape=1, preferredIndex=3
}
StaticPopupDialogs["RAID_POINTS_RESET_ALL"] = {
    text="Reset ALL points, history and the round number? This cannot be undone.",
    button1=YES, button2=NO,
    OnAccept=function()
        db.points={}; db.history={}; db.current={}; db.roundCounts={}; db.round=1
        roster(); refresh(); msg("All results have been reset.")
    end,
    timeout=0, whileDead=1, hideOnEscape=1, preferredIndex=3
}
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("RAID_ROSTER_UPDATE")
addon:RegisterEvent("PARTY_MEMBERS_CHANGED")
addon:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= "RaidPointsManager" then return end
        if type(RaidPointsManagerDB) ~= "table" then RaidPointsManagerDB={} end
        db = RaidPointsManagerDB
        -- v1.13: restore launcher after older builds may have hidden it accidentally.
        if not db.minimapIconRestoredV113 then
            db.minimapHidden = false
            db.minimapIconRestoredV113 = true
        end
        if type(db.backgroundIndex) ~= "number" or db.backgroundIndex < 1 or db.backgroundIndex > #backgroundOptions then db.backgroundIndex=1 end
        if type(db.backgroundOpacity) ~= "number" then db.backgroundOpacity=85 end
        if type(db.fontIndex) ~= "number" or db.fontIndex < 1 or db.fontIndex > #fontOptions then db.fontIndex=1 end
        if type(db.manualPlayers) ~= "table" then db.manualPlayers={} end
        if type(db.manualGroups) ~= "table" then db.manualGroups={} end
        if type(db.points) ~= "table" then db.points={} end
        if type(db.history) ~= "table" then db.history={} end
        if type(db.current) ~= "table" then db.current={} end
        if type(db.roundCounts) ~= "table" then db.roundCounts={} end
        if type(db.round) ~= "number" or db.round < 1 then db.round=1 end
        -- Older versions stored individual clicks; keep accumulated totals,
        -- but begin a new shared-round session to avoid double counting.
        if db.rounds then db.rounds=nil end
        build(); applyAppearance(); roster(); refresh(); window:Hide(); createMinimapButton()
        SLASH_RAIDPOINTSMANAGER1="/rp"
        SLASH_RAIDPOINTSMANAGER2="/raidpoints"
        SlashCmdList["RAIDPOINTSMANAGER"]=function(command)
            command = (command or ""):lower():match("^%s*(.-)%s*$")
            if command == "icon" or command == "minimap" then
                db.minimapHidden = false
                updateMinimapPosition(); minimapButton:Show()
                msg("Minimap icon shown. Right-click it to hide.")
            else
                toggleWindow()
            end
        end
        msg("Version 1.14 loaded. Left-click minimap icon or type /rp to open.")
    elseif db and refresh then roster(); refresh() end
end)
