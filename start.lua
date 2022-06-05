--- @type mq
local mq = require 'mq'
--- @type ImGui
require 'ImGui'
local LIP = require 'ma.LIP'
local globals = require 'ma.globals'
local utils = require 'ma.utils'

globals.CurrentSchema = 'ma'
globals.Schema = require('ma.schemas.'..globals.CurrentSchema)

-- Animations for drawing spell/item icons
local animSpellIcons = mq.FindTextureAnimation('A_SpellIcons')
local animItems = mq.FindTextureAnimation('A_DragItem')
-- Blue and yellow icon border textures
local animBlueWndPieces = mq.FindTextureAnimation('BlueIconBackground')
animBlueWndPieces:SetTextureCell(1)
local animYellowWndPieces = mq.FindTextureAnimation('YellowIconBackground')
animYellowWndPieces:SetTextureCell(1)
local animRedWndPieces = mq.FindTextureAnimation('RedIconBackground')
animRedWndPieces:SetTextureCell(1)

-- UI State
local open = true
local shouldDrawUI = true
local terminate = false
local initialRun = true
local leftPanelDefaultWidth = 150
local leftPanelWidth = 150

local selectedListItem = {nil, 0} -- {key, index}
local selectedUpgrade = nil
local selectedSection = 'General' -- Left hand menu selected item

globals.MyServer = mq.TLO.EverQuest.Server()
globals.MyName = mq.TLO.Me.CleanName()
globals.MyLevel = mq.TLO.Me.Level()
globals.MyClass = mq.TLO.Me.Class.ShortName():lower()

globals.MAUI_INI = ('%s/%s_%s.ini'):format(mq.configDir, globals.MyServer, globals.MyName)
local maui_ini_key = 'MAUI'
if utils.FileExists(globals.MAUI_INI) then
    globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
end
if not globals.MAUI_Config or not globals.MAUI_Config[maui_ini_key] or not globals.MAUI_Config[maui_ini_key]['StartCommand'] then
    globals.MAUI_Config = {[maui_ini_key] = {['StartCommand'] = globals.Schema['StartCommands'][1],}}
end

local selected_start_command = nil
for _,startcommand in ipairs(globals.Schema['StartCommands']) do
    if startcommand == globals.MAUI_Config[maui_ini_key]['StartCommand'] then
        selected_start_command = startcommand
    end
end
if not selected_start_command then
    if globals.MAUI_Config[maui_ini_key]['StartCommand'] then
        selected_start_command = 'custom'
    else
        selected_start_command = globals.Schema['StartCommands'][1]
    end
end

-- Storage for spell/AA/disc picker
local spells, altAbilities, discs = {categories={}},{},{}

local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.Hideable, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.BordersOuter)

--local customSections = require('ma.addons.'..globals.CurrentSchema)
local ok, customSections = pcall(require, 'ma.addons.'..globals.CurrentSchema)
if not ok then customSections = nil end

local function SaveMAUIConfig()
    -- Reload the maui.ini before saving to try and prevent writing stale data
    local tmpStartCommand = globals.MAUI_Config[maui_ini_key]['StartCommand']
    if utils.FileExists(globals.MAUI_INI) then
        globals.MAUI_Config = LIP.load(globals.MAUI_INI, false)
    else
        globals.MAUI_Config = {}
    end
    globals.MAUI_Config[maui_ini_key] = {['StartCommand'] = tmpStartCommand, ['INIFile'] = globals.INIFile}
    LIP.save_simple(globals.MAUI_INI, globals.MAUI_Config)
end

local function Save()
    -- Set "NULL" string values to nil so they aren't saved
    for sectionName,sectionProperties in pairs(globals.Config) do
        for key,value in pairs(sectionProperties) do
            if value == 'NULL' then
                -- Replace and XYZCond#=FALSE with nil as well if no corresponding XYZ# value
                local word = string.match(key, '[^%d]+')
                local number = string.match(key, '%d+')
                if number then
                    globals.Config[sectionName][word..'Cond'..number] = nil
                end
                globals.Config[sectionName][key] = nil
            end
        end
    end
    if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
        globals.INIFile = globals.INIFile .. '.ini'
    end
    LIP.save(mq.configDir..'/'..globals.INIFile, globals.Config, globals.Schema)
    SaveMAUIConfig()
end

-- Sort spells by level
local SpellSorter = function(a, b)
    -- spell level is in spell[1], name in spell[2]
    if a[1] < b[1] then
        return false
    elseif b[1] < a[1] then
        return true
    else
        return false
    end
end

local function AddSpellToMap(spell)
    if not spells[spell.Category()] then
        spells[spell.Category()] = {subcategories={}}
        table.insert(spells.categories, spell.Category())
    end
    if not spells[spell.Category()][spell.Subcategory()] then
        spells[spell.Category()][spell.Subcategory()] = {}
        table.insert(spells[spell.Category()].subcategories, spell.Subcategory())
    end
    if spell.Level() >= globals.MyLevel-30 then
        local name = spell.Name():gsub(' Rk%..*', '')
        table.insert(spells[spell.Category()][spell.Subcategory()], {spell.Level(), name})
    end
end

local function SortSpellMap()
    -- sort categories and subcategories alphabetically, spells by level
    table.sort(spells.categories)
    for category,subcategories in pairs(spells) do
        if category ~= 'categories' then
            table.sort(spells[category].subcategories)
            for subcategory,subcatspells in pairs(subcategories) do
                if subcategory ~= 'subcategories' then
                    table.sort(subcatspells, SpellSorter)
                end
            end
        end
    end
end

-- Ability menu initializers
local function InitSpellTree()
    -- Build spell tree for picking spells
    for spellIter=1,960 do
        local spell = mq.TLO.Me.Book(spellIter)
        if spell() then
            AddSpellToMap(spell)
        end
    end
    SortSpellMap()
end

local function InitAATree()
    -- TODO: what's the right way to loop through activated abilities?
    for aaIter=1,10000 do
        if mq.TLO.Me.AltAbility(aaIter)() and mq.TLO.Me.AltAbility(aaIter).Spell() then
            table.insert(altAbilities, mq.TLO.Me.AltAbility(aaIter).Name())
        end
        aaIter = aaIter + 1
    end
    table.sort(altAbilities)
end

local function InitDiscTree()
    -- Build disc tree for picking discs
    -- TODO: split up by timers? haven't really looked at discs yet
    local discIter = 1
    repeat
        local name = mq.TLO.Me.CombatAbility(discIter).Name():gsub(' Rk%..*', '')
        table.insert(discs, name)
        discIter = discIter + 1
    until mq.TLO.Me.CombatAbility(discIter)() == nil
    table.sort(discs)
end

--Given some spell data input, determine whether a better spell with the same inputs exists
local function GetSpellUpgrade(targetType, subCat, numEffects, minLevel)
    local max = 0
    local max2 = 0
    local maxName = ''
    local maxLevel = 0
    for i=1,960 do
        local valid = true
        local spell = mq.TLO.Me.Book(i)
        if not spell.ID() then
            valid = false
        elseif spell.Subcategory() ~= subCat then
            valid = false
        elseif spell.TargetType() ~= targetType then
            valid = false
        elseif spell.NumEffects() ~= numEffects then
            valid = false
        elseif spell.Level() <= minLevel then
            valid = false
        end
        if valid then
            -- TODO: several trigger spells i don't think this would handle properly...
            -- 470 == trigger best in spell group
            -- 374 == trigger spell
            -- 340 == chance spell
            if spell.HasSPA(470)() or spell.HasSPA(374)() or spell.HasSPA(340)() then
                for eIdx=1,spell.NumEffects() do
                    if spell.Trigger(eIdx)() then
                        for SPAIdx=1,spell.Trigger(eIdx).NumEffects() do
                            if spell.Trigger(eIdx).Base(SPAIdx)() < -1 then
                                if spell.Trigger(eIdx).Base(SPAIdx)() < max then
                                    max = spell.Trigger(eIdx).Base(SPAIdx)()
                                    maxName = spell.Name():gsub(' Rk%..*', '')
                                end
                            else
                                if spell.Trigger(eIdx).Base(SPAIdx)() > max then
                                    max = spell.Trigger(eIdx).Base(SPAIdx)()
                                    maxName = spell.Name():gsub(' Rk%..*', '')
                                end
                            end
                        end
                    end
                end
                -- TODO: this won't handle spells whos trigger SPA is just the illusion portion
            elseif spell.SPA() then
                for SPAIdx=1,spell.NumEffects() do
                    --print(string.format('[%s] .Base: %d, Base2: %d, Max: %d', spell.Name(), spell.Base(SPAIdx)(), spell.Base2(SPAIdx)(), spell.Max(SPAIdx)()))
                    if spell.Base(SPAIdx)() < -1 then
                        if spell.Base(SPAIdx)() < max then
                            max = spell.Base(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        elseif spell.Base2(SPAIdx)() ~= 0 and spell.Base2(SPAIdx)() > max2 then
                            max2 = spell.Base2(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        end
                    else
                        if spell.Base(SPAIdx)() > max then
                            max = spell.Base(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        elseif spell.Base2(SPAIdx)() ~= 0 and spell.Base2(SPAIdx)() > max2 then
                            max2 = spell.Base2(SPAIdx)()
                            maxName = spell.Name():gsub(' Rk%..*', '')
                        end
                    end
                end
            end
        end
    end
    return maxName
end

-- ImGui functions

-- Color spell names in spell picker similar to the spell bar context menus
local function SetSpellTextColor(spell)
    local target = mq.TLO.Spell(spell).TargetType()
    if target == 'Single' or target == 'Line of Sight' or target == 'Undead' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif target == 'Self' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    elseif target == 'Group v2' or target == 'Group v1' or target == 'AE PC v2' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 1, 1)
    elseif target == 'Beam' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 1, 1)
    elseif target == 'Targeted AE' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.5, 0, 1)
    elseif target == 'PB AE' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 0.5, 1, 1)
    elseif target == 'Pet' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif target == 'Pet2' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif target == 'Free Target' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
    end
end

local memspell = nil
local memgem = 0
-- Recreate the spell bar context menu
-- sectionName+key+index defines where to store the result
-- selectedIdx is used to clear spell upgrade input incase of updating over an existing entry
local function DrawSpellPicker(sectionName, key, index)
    if not globals.Config[sectionName][key..index] then
        globals.Config[sectionName][key..index] = ''
    end
    local valueParts = nil
    if type(globals.Config[sectionName][key..index]) == "string" then
        valueParts = utils.Split(globals.Config[sectionName][key..index],'|',1)
    elseif type(globals.Config[sectionName][key..index]) == "number" then
        valueParts = {tostring(globals.Config[sectionName][key..index])}
    end
    -- Right click context menu popup on list buttons
    if ImGui.BeginPopupContextItem('##rcmenu'..sectionName..key..index) then
        -- Top level 'Spells' menu item
        if #spells.categories > 0 then
            if ImGui.BeginMenu('Spells##rcmenu'..sectionName..key) then
                for _,category in ipairs(spells.categories) do
                    -- Spell Subcategories submenu
                    if ImGui.BeginMenu(category..'##rcmenu'..sectionName..key..category) then
                        for _,subcategory in ipairs(spells[category].subcategories) do
                            -- Subcategory Spell menu
                            if #spells[category][subcategory] > 0 and ImGui.BeginMenu(subcategory..'##'..sectionName..key..subcategory) then
                                for _,spell in ipairs(spells[category][subcategory]) do
                                    -- spell[1]=level, spell[2]=name
                                    SetSpellTextColor(spell[2])
                                    if ImGui.MenuItem(spell[1]..' - '..spell[2]..'##'..sectionName..key..subcategory) then
                                        valueParts[1] = spell[2]
                                        selectedUpgrade = nil
                                    end
                                    ImGui.PopStyleColor()
                                end
                                ImGui.EndMenu()
                            end
                        end
                        ImGui.EndMenu()
                    end
                end
                ImGui.EndMenu()
            end
        end
        -- Top level 'AAs' menu item
        if sectionName ~= 'MySpells' and #altAbilities > 0 then
            local menuHeight = -1
            if #altAbilities > 25 then
                menuHeight = ImGui.GetTextLineHeight()*25
            end
            ImGui.SetNextWindowSize(250, menuHeight)
            if ImGui.BeginMenu('AAs##rcmenu'..sectionName..key) then
                for _,altAbility in ipairs(altAbilities) do
                    if ImGui.MenuItem(altAbility..'##aa'..sectionName..key) then
                        valueParts[1] = altAbility
                    end
                end
                ImGui.EndMenu()
            end
        end
        -- Top level 'Discs' menu item
        if sectionName ~= 'MySpells' and #discs > 0 then
            local menuHeight = -1
            if #discs > 25 then
                menuHeight = ImGui.GetTextLineHeight()*25
            end
            ImGui.SetNextWindowSize(250, menuHeight)
            if ImGui.BeginMenu('Combat Abilities##rcmenu'..sectionName..key) then
                for _,disc in ipairs(discs) do
                    if ImGui.MenuItem(disc..'##disc'..sectionName..key) then
                        valueParts[1] = disc
                    end
                end
                ImGui.EndMenu()
            end
        end
        if valueParts[1] and mq.TLO.Me.Book(mq.TLO.Spell(valueParts[1]).RankName())() then
            if ImGui.MenuItem('Memorize Spell') then
                for i=1,13 do
                    if not mq.TLO.Me.Gem(i)() then
                        memspell = valueParts[1]
                        memgem = i
                        break
                    end
                end
            end
        end
        ImGui.EndPopup()
    end
    globals.Config[sectionName][key..index] = table.concat(valueParts, '|')
    if globals.Config[sectionName][key..index] == '|' then
        globals.Config[sectionName][key..index] = 'NULL'
    end
end

local function DrawSelectedSpellUpgradeButton(spell)
    local upgradeValue = nil
    -- Avoid finding the upgrade more than once
    if not selectedUpgrade then
        selectedUpgrade = GetSpellUpgrade(spell.TargetType(), spell.Subcategory(), spell.NumEffects(), spell.Level())
    end
    -- Upgrade found? display the upgrade button
    if selectedUpgrade ~= '' and selectedUpgrade ~= spell.Name() then
        if ImGui.Button('Upgrade Available - '..selectedUpgrade) then
            upgradeValue = selectedUpgrade
            selectedUpgrade = nil
        end
    end
    return upgradeValue
end

local function DrawSelectedSpellDowngradeButton(spell)
    local upgradeValue = nil
    -- Avoid finding the upgrade more than once
    if not selectedUpgrade then
        selectedUpgrade = GetSpellUpgrade(spell.TargetType(), spell.Subcategory(), spell.NumEffects(), 0)
    end
    -- Upgrade found? display the upgrade button
    if selectedUpgrade ~= '' and selectedUpgrade ~= spell.Name() then
        if ImGui.Button('Downgrade Available - '..selectedUpgrade) then
            upgradeValue = selectedUpgrade
            selectedUpgrade = nil
        end
    end
    return upgradeValue
end

local function CheckInputType(key, value, typestring, inputtype)
    if type(value) ~= typestring then
        utils.printf('\arWARNING [%s]: %s value is not a %s: type=%s value=%s\a-x', key, inputtype, typestring, type(value), tostring(value))
    end
end

local function DrawKeyAndInputText(keyText, label, value, helpText)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(keyText)
    ImGui.PopStyleColor()
    ImGui.SameLine()
    utils.HelpMarker(helpText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(175)
    -- the first part, spell/item/disc name, /command, etc
    CheckInputType(label, value, 'string', 'InputText')
    return ImGui.InputText(label, tostring(value))
end

-- Draw the value and condition of the selected list item
local function DrawSelectedListItem(sectionName, key, value)
    local valueKey = key..selectedListItem[2]
    -- make sure values not nil so imgui inputs don't barf
    if globals.Config[sectionName][valueKey] == nil then
        globals.Config[sectionName][valueKey] = 'NULL'
    end
    -- split the value so we can update spell name and stuff after the | individually
    local valueParts = utils.Split(globals.Config[sectionName][valueKey], '|', 1)
    -- the first part, spell/item/disc name, /command, etc
    if not valueParts[1] then valueParts[1] = '' end
    -- the rest of the stuff after the first |, classes, percents, oog, etc
    if not valueParts[2] then valueParts[2] = '' end

    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 1, 1)
    ImGui.Text(string.format('%s%d', key, selectedListItem[2]))
    ImGui.PopStyleColor()
    valueParts[1] = DrawKeyAndInputText('Name: ', '##'..sectionName..valueKey, valueParts[1], value['Tooltip'])
    -- prevent | in the ability name field, or else things get ugly in the options field
    if valueParts[1]:find('|') then valueParts[1] = valueParts[1]:match('[^|]+') end
    valueParts[2] = DrawKeyAndInputText('Options: ', '##'..sectionName..valueKey..'options', valueParts[2], value['OptionsTooltip'])
    if value['Conditions'] then
        local valueCondKey = key..'Cond'..selectedListItem[2]
        if globals.Config[sectionName][valueCondKey] == nil then
            globals.Config[sectionName][valueCondKey] = 'NULL'
        end
        globals.Config[sectionName][valueCondKey] = DrawKeyAndInputText('Conditions: ', '##cond'..sectionName..valueKey, globals.Config[sectionName][valueCondKey], value['CondTooltip'])
    end
    local spell = mq.TLO.Spell(valueParts[1])
    if mq.TLO.Me.Book(spell.RankName())() then
        local upgradeResult = DrawSelectedSpellUpgradeButton(spell)
        if upgradeResult then valueParts[1] = upgradeResult end
    elseif spell then
        local upgradeResult = DrawSelectedSpellDowngradeButton(spell)
        if upgradeResult then valueParts[1] = upgradeResult end
    end
    if valueParts[1] and string.len(valueParts[1]) > 0 then
        globals.Config[sectionName][valueKey] = valueParts[1]
        if valueParts[2] and string.len(valueParts[2]) > 0 then
            globals.Config[sectionName][valueKey] = globals.Config[sectionName][valueKey]..'|'..valueParts[2]:gsub('|$','')
        end
    else
        globals.Config[sectionName][valueKey] = ''
    end
    ImGui.Separator()
end

local function DrawPlainListButton(sectionName, key, listIdx, iconSize)
    -- INI value is set to non-spell/item
    if ImGui.Button(listIdx..'##'..sectionName..key, iconSize[1], iconSize[2]) then
        if type(listIdx) == 'number' then
            if mq.TLO.Cursor() then
                globals.Config[sectionName][key..listIdx] = mq.TLO.Cursor.Name()
            else
                selectedListItem = {key, listIdx}
                selectedUpgrade = nil
            end
        else
            if mq.TLO.Cursor() then
                globals.Config[sectionName][key] = mq.TLO.Cursor.Name()
            end
        end
    elseif type(listIdx) == 'number' then
        if not mq.TLO.Cursor() and ImGui.BeginDragDropSource() then
            ImGui.SetDragDropPayload("ListBtn", listIdx)
            ImGui.Button(listIdx..'##'..sectionName..key, iconSize[1], iconSize[2])
            ImGui.EndDragDropSource()
        end
    end
end

local function DrawTooltip(text)
    if ImGui.IsItemHovered() and text and string.len(text) > 0 then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
        ImGui.Text(text)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

local function ValidSpellOrItem(iniValue)
    local valid = false
    if not iniValue then
        -- count unset INI entry as valid
        valid = true
    else
        if mq.TLO.Spell(iniValue)() then
            if mq.TLO.Me.Book(mq.TLO.Spell(iniValue).RankName())() then
                valid = true
            elseif mq.TLO.Me.AltAbility(iniValue)() then
                valid = true
            elseif mq.TLO.Me.CombatAbility(iniValue)() then
                valid = true
            end
        elseif mq.TLO.FindItem(iniValue)() then
            valid = true
        end
    end
    return valid
end

local function DrawSpellIconOrButton(sectionName, key, index)
    local iniValue = nil
    if globals.Config[sectionName][key..index] and globals.Config[sectionName][key..index] ~= 'NULL' then
        if type(globals.Config[sectionName][key..index]) == "string" then
            iniValue = utils.Split(globals.Config[sectionName][key..index],'|',1)[1]
        elseif type(globals.Config[sectionName][key..index]) == "number" then
            iniValue = tostring(globals.Config[sectionName][key..index])
        end
    end
    local charHasAbility = ValidSpellOrItem(iniValue)
    local iconSize = {30,30} -- default icon size
    if type(index) == 'number' then
        local x,y = ImGui.GetCursorPos()
        if not charHasAbility then
            ImGui.DrawTextureAnimation(animRedWndPieces, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x+2)
            ImGui.SetCursorPosY(y+2)
            iconSize = {26,26}
        end
    end
    if iniValue then
        -- Use first part of INI value as spell or item name to lookup icon
        if mq.TLO.Spell(iniValue)() then
            -- Need to create a group for drag/drop to work, doesn't seem to work with just the texture animation?
            ImGui.BeginGroup()
            local x,y = ImGui.GetCursorPos()
            ImGui.Button('##'..index..sectionName..key, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x)
            ImGui.SetCursorPosY(y)
            local spellIcon = mq.TLO.Spell(iniValue).SpellIcon()
            animSpellIcons:SetTextureCell(spellIcon)
            ImGui.DrawTextureAnimation(animSpellIcons, iconSize[1], iconSize[2])
            ImGui.EndGroup()
        elseif mq.TLO.FindItem(iniValue)() then
            -- Need to create a group for drag/drop to work, doesn't seem to work with just the texture animation?
            ImGui.BeginGroup()
            local x,y = ImGui.GetCursorPos()
            ImGui.Button('##'..index..sectionName..key, iconSize[1], iconSize[2])
            ImGui.SetCursorPosX(x)
            ImGui.SetCursorPosY(y)
            local itemIcon = mq.TLO.FindItem(iniValue).Icon()
            animItems:SetTextureCell(itemIcon-500)
            ImGui.DrawTextureAnimation(animItems, iconSize[1], iconSize[2])
            ImGui.EndGroup()
        else
            DrawPlainListButton(sectionName, key, index, iconSize)
        end
        DrawTooltip(iniValue)
        -- Handle clicks on spell icon animations that aren't buttons
        if ImGui.BeginDragDropTarget() then
            local payload = ImGui.AcceptDragDropPayload("ListBtn")
            if payload ~= nil then
                local num = payload.Data;
                -- swap the list entries
                globals.Config[sectionName][key..index], globals.Config[sectionName][key..num] = globals.Config[sectionName][key..num], globals.Config[sectionName][key..index]
                globals.Config[sectionName][key..'Cond'..index], globals.Config[sectionName][key..'Cond'..num] = globals.Config[sectionName][key..'Cond'..num], globals.Config[sectionName][key..'Cond'..index]
            end
            ImGui.EndDragDropTarget()
        elseif ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) and type(index) == 'number' then
            if mq.TLO.Cursor() then
                globals.Config[sectionName][key..index] = mq.TLO.Cursor.Name()
            else
                selectedListItem = {key, index}
                selectedUpgrade = nil
            end
        elseif ImGui.IsItemHovered() and ImGui.IsMouseDown(ImGuiMouseButton.Left) and type(index) == 'number' then
            if not mq.TLO.Cursor() and ImGui.BeginDragDropSource() then
                ImGui.SetDragDropPayload("ListBtn", index)
                ImGui.Button(index..'##'..sectionName..key, iconSize[1], iconSize[2])
                ImGui.EndDragDropSource()
            end
        end
        -- Spell picker context menu on right click button
        DrawSpellPicker(sectionName, key, index)
    else
        -- No INI value assigned yet for this key
        DrawPlainListButton(sectionName, key, index, iconSize)
        DrawSpellPicker(sectionName, key, index)
        if ImGui.BeginDragDropTarget() then
            local payload = ImGui.AcceptDragDropPayload("ListBtn")
            if payload ~= nil then
                local num = payload.Data;
                -- swap the list entries
                globals.Config[sectionName][key..index], globals.Config[sectionName][key..num] = globals.Config[sectionName][key..num], globals.Config[sectionName][key..index]
                globals.Config[sectionName][key..'Cond'..index], globals.Config[sectionName][key..'Cond'..num] = globals.Config[sectionName][key..'Cond'..num], globals.Config[sectionName][key..'Cond'..index]
            end
            ImGui.EndDragDropTarget()
        end
    end
end

-- Draw 0..N buttons based on value of XYZSize input
local function DrawList(sectionName, key, value)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(key..'Size: ')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    utils.HelpMarker(value['SizeTooltip'])
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    local size = globals.Config[sectionName][key..'Size']
    if size == nil or type(size) ~= 'number' then
        CheckInputType(key..'Size', size, 'number', 'InputInt')
        size = 0
    end
    ImGui.SetCursorPosX(175)
    -- Set size of list and check boundaries
    size = ImGui.InputInt('##sizeinput'..sectionName..key, size)
    if size < 0 then
        size = 0
    elseif size > value['Max'] then
        size = value['Max']
    end
    ImGui.PopItemWidth()
    local xOffset,yOffset = ImGui.GetCursorPos()
    local avail = ImGui.GetContentRegionAvail()
    local iconsPerRow = math.floor(avail/38)
    if iconsPerRow == 0 then iconsPerRow = 1 end
    for i=1,size do
        local offsetMod = math.floor((i-1)/iconsPerRow)
        ImGui.SetCursorPosY(yOffset+(36*offsetMod))
        DrawSpellIconOrButton(sectionName, key, i)
        if i%iconsPerRow ~= 0 and i < size then
            -- Some silliness instead of sameline due to the offset changes for red frames around missing abilities in list items
            -- Just let it be
            ImGui.SetCursorPosX(xOffset+(30*(i%iconsPerRow))+(6*(i%iconsPerRow)))
            ImGui.SetCursorPosY(yOffset)
        end
    end
    ImGui.SetCursorPosY(yOffset+38*(math.floor((size-1)/iconsPerRow)+1))
    globals.Config[sectionName][key..'Size'] = size
end

local function DrawMultiPartProperty(sectionName, key, value)
    -- TODO: what's a nice clean way to represent values which are multiple parts? 
    -- Currently just using this experimentally with RezAcceptOn
    local parts = utils.Split(globals.Config[sectionName][key], '|',1)
    for partIdx,part in ipairs(value['Parts']) do
        if part['Type'] == 'SWITCH' then
            ImGui.Text(part['Name']..': ')
            ImGui.SameLine()
            local value = utils.InitCheckBoxValue(tonumber(parts[partIdx]))
            CheckInputType(key, value, 'boolean', 'Checkbox')
            parts[partIdx] = ImGui.Checkbox('##'..key, value)
            if parts[partIdx] then parts[partIdx] = '1' else parts[partIdx] = '0' end
        elseif part['Type'] == 'NUMBER' then
            if not parts[partIdx] or parts[partIdx] == 'NULL' then parts[partIdx] = 0 end
            ImGui.Text(part['Name']..': ')
            ImGui.SameLine()
            ImGui.PushItemWidth(100)
            local value = tonumber(parts[partIdx])
            CheckInputType(key, value, 'number', 'InputInt')
            parts[partIdx] = ImGui.InputInt('##'..sectionName..key..partIdx, value)
            ImGui.PopItemWidth()
            if part['Min'] and parts[partIdx] < part['Min'] then
                parts[partIdx] = part['Min']
            elseif part['Max'] and parts[partIdx] > part['Max'] then
                parts[partIdx] = part['Max']
            end
            parts[partIdx] = tostring(parts[partIdx])
        end
        globals.Config[sectionName][key] = table.concat(parts, '|')
        if partIdx == 1 then
            ImGui.SameLine()
        end
    end
end

-- Draw a generic section key/value property
local function DrawProperty(sectionName, key, value)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(key..': ')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    utils.HelpMarker(value['Tooltip'])
    ImGui.SameLine()
    if globals.Config[sectionName][key] == nil then
        globals.Config[sectionName][key] = 'NULL'
    end
    ImGui.SetCursorPosX(175)
    if value['Type'] == 'SWITCH' then
        local initialValue = utils.InitCheckBoxValue(globals.Config[sectionName][key])
        CheckInputType(key, initialValue, 'boolean', 'Checkbox')
        globals.Config[sectionName][key] = ImGui.Checkbox('##'..key, initialValue)
    elseif value['Type'] == 'SPELL' then
        DrawSpellIconOrButton(sectionName, key, '')
        ImGui.SameLine()
        ImGui.PushItemWidth(350)
        local initialValue = globals.Config[sectionName][key]
        CheckInputType(key, initialValue, 'string', 'InputText')
        globals.Config[sectionName][key] = ImGui.InputText('##textinput'..sectionName..key, tostring(initialValue))
        ImGui.PopItemWidth()
    elseif value['Type'] == 'NUMBER' then
        local initialValue = globals.Config[sectionName][key]
        if not initialValue or initialValue == 'NULL' or type(initialValue) ~= 'number' then
            CheckInputType(key, initialValue, 'number', 'InputInt')
            initialValue = 0
        end
        ImGui.PushItemWidth(350)
        globals.Config[sectionName][key] = ImGui.InputInt('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
        if value['Min'] and globals.Config[sectionName][key] < value['Min'] then
            globals.Config[sectionName][key] = value['Min']
        elseif value['Max'] and globals.Config[sectionName][key] > value['Max'] then
            globals.Config[sectionName][key] = value['Max']
        end
    elseif value['Type'] == 'STRING' then
        ImGui.PushItemWidth(350)
        local initialValue = tostring(globals.Config[sectionName][key])
        CheckInputType(key, initialValue, 'string', 'InputText')
        globals.Config[sectionName][key] = ImGui.InputText('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
    elseif value['Type'] == 'MULTIPART' then
        DrawMultiPartProperty(sectionName, key, value)
    end
end

-- Draw main On/Off switches for an INI section
local function DrawSectionControlSwitches(sectionName, sectionProperties)
    if sectionProperties['On'] then
        if sectionProperties['On']['Type'] == 'SWITCH' then
            local value = utils.InitCheckBoxValue(globals.Config[sectionName][sectionName..'On'])
            CheckInputType(sectionName..'On', value, 'boolean', 'Checkbox')
            globals.Config[sectionName][sectionName..'On'] = ImGui.Checkbox(sectionName..'On', value)
        elseif sectionProperties['On']['Type'] == 'NUMBER' then
            -- Type=NUMBER control switch mostly a special case for DPS section only
            if not globals.Config[sectionName][sectionName..'On'] then globals.Config[sectionName][sectionName..'On'] = 0 end
            ImGui.PushItemWidth(100)
            globals.Config[sectionName][sectionName..'On'] = ImGui.InputInt(sectionName..'On', globals.Config[sectionName][sectionName..'On'])
            ImGui.PopItemWidth()
            if sectionProperties['On']['Min'] and globals.Config[sectionName][sectionName..'On'] < sectionProperties['On']['Min'] then
                globals.Config[sectionName][sectionName..'On'] = sectionProperties['On']['Min']
            elseif sectionProperties['On']['Max'] and globals.Config[sectionName][sectionName..'On'] > sectionProperties['On']['Max'] then
                globals.Config[sectionName][sectionName..'On'] = sectionProperties['On']['Max']
            end
        end
        if sectionProperties['COn'] then ImGui.SameLine() end
    end
    if sectionProperties['COn'] then
        globals.Config[sectionName][sectionName..'COn'] = ImGui.Checkbox(sectionName..'COn', utils.InitCheckBoxValue(globals.Config[sectionName][sectionName..'COn']))
    end
    ImGui.Separator()
end

local function DrawSpellsGemList(spellSection)
    local _,yOffset = ImGui.GetCursorPos()
    local avail = ImGui.GetContentRegionAvail()
    local iconsPerRow = math.floor(avail/36)
    if iconsPerRow == 0 then iconsPerRow = 1 end
    for i=1,13 do
        local offsetMod = math.floor((i-1)/iconsPerRow)
        ImGui.SetCursorPosY(yOffset+(34*offsetMod))
        DrawSpellIconOrButton(spellSection, 'Gem', i)
        if i%iconsPerRow ~= 0 and i < 13 then
            ImGui.SameLine()
        end
    end
end

local function DrawSpells(spellSection)
    ImGui.TextColored(1, 1, 0, 1, spellSection)
    if globals.Config[spellSection] then
        DrawSpellsGemList(spellSection)
    end
    if ImGui.Button('Update from spell bar') then
        if not globals.Config[spellSection] then globals.Config[spellSection] = {} end
        for i=1,13 do
            globals.Config[spellSection]['Gem'..i] = mq.TLO.Me.Gem(i).Name()
        end
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
    end
end

-- Draw an INI section tab
local function DrawSection(sectionName, sectionProperties)
    if not globals.Config[sectionName] then
        globals.Config[sectionName] = {}
    end
    -- Draw main section control switches first
    if sectionProperties['Controls'] then
        DrawSectionControlSwitches(sectionName, sectionProperties['Controls'])
    end
    if ImGui.BeginChild('SectionProperties') then
        if sectionName == 'SpellSet' then
            -- special case for SpellSet tab to draw save spell set button (MA)
            DrawSpells('MySpells')
        elseif sectionName == 'Spells' then
            -- special case for Spells tab (KA)
            DrawSpells('Spells')
            -- Generic properties last
            for key,value in pairs(sectionProperties['Properties']) do
                if value['Type'] ~= 'LIST' then
                    DrawProperty(sectionName, key, value)
                end
            end
        else
            if selectedListItem[1] then
                if ImGui.Button('Back to List') then
                    selectedListItem = {nil, 0}
                    selectedUpgrade = nil
                else
                    DrawSpellIconOrButton(sectionName, selectedListItem[1], selectedListItem[2])
                    DrawSelectedListItem(sectionName, selectedListItem[1], sectionProperties['Properties'][selectedListItem[1]])
                end
            else
                -- Draw List properties before general properties
                for key,value in pairs(sectionProperties['Properties']) do
                    if value['Type'] == 'LIST' then
                        DrawList(sectionName, key, value)
                    end
                end
                -- Generic properties last
                for key,value in pairs(sectionProperties['Properties']) do
                    if value['Type'] ~= 'LIST' then
                        DrawProperty(sectionName, key, value)
                    end
                end
            end
        end
    end
    ImGui.EndChild()
end

local function DrawSplitter(thickness, size0, min_size0)
    local x,y = ImGui.GetCursorPos()
    local delta = 0
    ImGui.SetCursorPosX(x + size0)

    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.6, 0.6, 0.6, 0.1)
    ImGui.Button('##splitter', thickness, -1)
    ImGui.PopStyleColor(3)

    ImGui.SetItemAllowOverlap()

    if ImGui.IsItemActive() then
        delta,_ = ImGui.GetMouseDragDelta()

        if delta < min_size0 - size0 then
            delta = min_size0 - size0
        end
        if delta > 200 - size0 then
            delta = 200 - size0
        end

        size0 = size0 + delta
        leftPanelWidth = size0
    else
        leftPanelDefaultWidth = leftPanelWidth
    end
    ImGui.SetCursorPosX(x)
    ImGui.SetCursorPosY(y)
end

local function LeftPaneWindow()
    local x,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("left", leftPanelWidth, y-1, true) then
        if ImGui.BeginTable('SelectSectionTable', 1, TABLE_FLAGS, 0, 0, 0.0) then
            ImGui.TableSetupColumn('Section Name',     0,   -1.0, 1)
            ImGui.TableSetupScrollFreeze(0, 1) -- Make row always visible
            ImGui.TableHeadersRow()

            for _,sectionName in ipairs(globals.Schema.Sections) do
                if globals.Schema[sectionName] and (not globals.Schema[sectionName].Classes or globals.Schema[sectionName].Classes[globals.MyClass]) then
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    local popStyleColor = false
                    if globals.Schema[sectionName]['Controls'] and globals.Schema[sectionName]['Controls']['On'] then
                        if not globals.Config[sectionName] or not globals.Config[sectionName][sectionName..'On'] or globals.Config[sectionName][sectionName..'On'] == 0 then
                            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                        end
                        popStyleColor = true
                    end
                    local sel = ImGui.Selectable(sectionName, selectedSection == sectionName)
                    if sel and selectedSection ~= sectionName then
                        selectedListItem = {nil,0}
                        selectedSection = sectionName
                    end
                    if popStyleColor then ImGui.PopStyleColor() end
                end
            end
            ImGui.Separator()
            ImGui.Separator()
            for section,_ in pairs(customSections) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                if ImGui.Selectable(section, selectedSection == section) then
                    selectedSection = section
                end
            end
            ImGui.EndTable()
        end
    end
    ImGui.EndChild()
end

local function RightPaneWindow()
    local x,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("right", x, y-1, true) then
        if customSections[selectedSection] then
            customSections[selectedSection]()
        else
            DrawSection(selectedSection, globals.Schema[selectedSection])
        end
    end
    ImGui.EndChild()
end

local function DrawWindowPanels()
    DrawSplitter(8, leftPanelDefaultWidth, 75)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 2, 2)
    LeftPaneWindow()
    ImGui.SameLine()
    RightPaneWindow()
    ImGui.PopStyleVar()
end

local function SetSchemaVars(selectedSchema)
    local ok, schemaMod = pcall(require, 'ma.schemas.'..selectedSchema)
    if not ok then print('Error loading schema for: '..selectedSchema) return false end
    ok, addonMod = pcall(require, 'ma.addons.'..selectedSchema)
    if not ok then print('Error loading schema for: '..selectedSchema) return false end

    customSections = addonMod
    globals.Schema = schemaMod
    globals.CurrentSchema = selectedSchema
    globals.INIFile = utils.FindINIFile()
    selectedSection = 'General'
    if globals.INIFile and utils.FileExists(mq.configDir..'/'..globals.INIFile) then
        globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
        globals.INIFileContents = utils.ReadRawINIFile()
        globals.INILoadError = ''
    else
        globals.INIFile = ''
        globals.Config = {}
    end
    return true
end

local function DrawComboBox(label, resultvar, options)
    if ImGui.BeginCombo(label, resultvar) then
        for i,j in pairs(options) do
            if ImGui.Selectable(j, j == resultvar) then
                resultvar = j
            end
        end
        ImGui.EndCombo()
    end
    return resultvar
end

local radioValue = 1
local function DrawWindowHeaderSettings()
    if #globals.Schemas > 1 then
        for idx, schema_kind in ipairs(globals.Schemas) do
            radioValue,_ = ImGui.RadioButton(schema_kind, radioValue, idx)
            ImGui.SameLine()
        end
        if globals.CurrentSchema ~= globals.Schemas[radioValue] then
            if not SetSchemaVars(globals.Schemas[radioValue]) then
                radioValue = 1
            end
        end
        ImGui.NewLine()
        ImGui.Separator()
    end

    ImGui.Text('INI File: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    ImGui.PushItemWidth(350)
    globals.INIFile,_ = ImGui.InputText('##INIInput', globals.INIFile)
    ImGui.SameLine()
    if ImGui.Button('Save INI') then
        Save()
        globals.INIFileContents = utils.ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Reload INI') then
        if globals.INIFile:sub(-string.len('.ini')) ~= '.ini' then
            globals.INIFile = globals.INIFile .. '.ini'
        end
        if utils.FileExists(mq.configDir..'/'..globals.INIFile) then
            globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
            globals.INILoadError = ''
        else
            globals.INILoadError = ('INI File %s/%s does not exist!'):format(mq.configDir, globals.INIFile)
        end
    end

    if globals.INILoadError ~= '' then
        ImGui.TextColored(1,0,0,1,globals.INILoadError)
    end

    local match_found = false
    for _,startcommand in ipairs(globals.Schema['StartCommands']) do
        if startcommand == globals.MAUI_Config[maui_ini_key]['StartCommand'] then
            selected_start_command = startcommand
            match_found = true
            break
        end
    end
    if not match_found then
        if globals.MAUI_Config[maui_ini_key]['StartCommand'] then
            selected_start_command = 'custom'
        else
            selected_start_command = globals.Schema['StartCommands'][1]
        end
    end

    ImGui.Separator()
    ImGui.Text('Start Command: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    ImGui.PushItemWidth(190)
    selected_start_command = DrawComboBox('##StartCommands', selected_start_command, globals.Schema['StartCommands'])
    ImGui.SameLine()
    ImGui.PushItemWidth(300)
    if selected_start_command == 'custom' then
        globals.MAUI_Config[maui_ini_key]['StartCommand'],_ = ImGui.InputText('##StartCommand', globals.MAUI_Config[maui_ini_key]['StartCommand'])
    else
        globals.MAUI_Config[maui_ini_key]['StartCommand'],_ = ImGui.InputText('##StartCommand', selected_start_command)
    end
    --ImGui.SameLine()
    ImGui.Text('Status: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    if not mq.TLO.Macro() or mq.TLO.Macro.Name() ~= 'muleassist.mac' then
        ImGui.TextColored(1, 0, 0, 1, 'STOPPED')
        ImGui.SameLine()
        if ImGui.Button('Start Macro') then
            mq.cmd(globals.MAUI_Config[maui_ini_key]['StartCommand'])
            SaveMAUIConfig()
        end
    elseif mq.TLO.Macro.Name() == 'muleassist.mac' then
        if mq.TLO.Macro.Paused() then
            ImGui.TextColored(1, 1, 0, 1, 'PAUSED')
            ImGui.SameLine()
            if ImGui.Button('End') then
                mq.cmd('/end')
            end
            ImGui.SameLine()
            if ImGui.Button('Resume') then
                mq.cmd('/mqp off')
            end
        else
            ImGui.TextColored(0, 1, 0, 1, 'RUNNING')
            ImGui.SameLine()
            if ImGui.Button('End') then
                mq.cmd('/end')
            end
            ImGui.SameLine()
            if ImGui.Button('Pause') then
                mq.cmd('/mqp on')
            end
        end
        ImGui.SameLine()
        ImGui.Text(string.format('Role: %s', mq.TLO.Macro.Variable('Role')()))
    end
    ImGui.Separator()
end

-- Thanks coldblooded!
local EQ_ICON_OFFSET = 500
local ICON_WIDTH = 40
local ICON_HEIGHT = 40
-- If there is an item on the cursor, display it.
local function display_item_on_cursor()
    if mq.TLO.Cursor() then
        local cursor_item = mq.TLO.Cursor -- this will be an MQ item, so don't forget to use () on the members!
        local mouse_x, mouse_y = ImGui.GetMousePos()
        local window_x, window_y = ImGui.GetWindowPos()
        local icon_x = mouse_x - window_x + 10
        local icon_y = mouse_y - window_y + 10
        ImGui.SetCursorPos(icon_x, icon_y)
        animItems:SetTextureCell(cursor_item.Icon() - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, ICON_WIDTH, ICON_HEIGHT)
    end
end

local MAUI = function()
    if not open then return end
    open, shouldDrawUI = ImGui.Begin('MAUI (v'..globals.Version..')###MuleAssist', open)
    if shouldDrawUI then
        -- these appear to be the numbers for the window on first use... probably shouldn't rely on them.
        if initialRun then
            if ImGui.GetWindowHeight() == 38 and ImGui.GetWindowWidth() == 32 then
                ImGui.SetWindowSize(727,487)
            elseif ImGui.GetWindowHeight() == 500 and ImGui.GetWindowWidth() == 500 then
                ImGui.SetWindowSize(727,487)
            end
            initialRun = false
        end
        DrawWindowHeaderSettings()
        DrawWindowPanels()
        display_item_on_cursor()
    end
    ImGui.End()
end

local function ShowHelp()
    print('\a-t[\ax\ayMAUI\ax\a-t]\ax Usage: /maui [show|hide|stop]')
end

local function BindMaui(args)
    if not args then
        ShowHelp()
    end
    local arglist = {args}
    if #arglist > 1 then
        ShowHelp()
    elseif arglist[1] == 'show' then
        open = true
    elseif arglist[1] == 'hide' then
        open = false
    elseif arglist[1] == 'stop' then
        open = false
        terminate = true
    end
end

local function NewSpellMemmed(line, spell)
    print(string.format('\a-t[\ax\ayMAUI\ax\a-t]\ax New spell memorized, updating spell list. \a-t(\ax\ay%s\ax\a-t)\ax', spell))
    -- Build spell tree for picking spells
    local spellNum = mq.TLO.Me.Book(spell)
    local spell = mq.TLO.Me.Book(spellNum)
    if spell() then
        AddSpellToMap(spell)
    end

    SortSpellMap()
end

-- Load INI into table as well as raw content
globals.INIFile = globals.MAUI_Config['INIFile'] or utils.FindINIFile()
if globals.INIFile and utils.FileExists(mq.configDir..'/'..globals.INIFile) then
    globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
    globals.INIFileContents = utils.ReadRawINIFile()
    globals.INILoadError = ''
else
    globals.INIFile = globals.Schema['INI_PATTERNS']['level']:format(globals.MyServer, globals.MyName, globals.MyLevel)
    globals.Config = {}
end

local initCo = coroutine.create(function()
    -- Initializing and sorting spell tree takes a few seconds, so run in parallel
    InitSpellTree()
    InitAATree()
    InitDiscTree()
end)
coroutine.resume(initCo)

mq.bind('/maui', BindMaui)

mq.event('NewSpellMemmed', '#*#You have finished scribing #1#.', NewSpellMemmed)

mq.imgui.init('MuleAssist', MAUI)

while not terminate do
    if coroutine.status(initCo) == 'suspended' then
        coroutine.resume(initCo)
    end
    mq.doevents()
    if memspell then
        local rankname = mq.TLO.Spell(memspell).RankName()
        mq.cmdf('/memspell %s "%s"', memgem, rankname)
        mq.delay('3s', function() return mq.TLO.Me.Gem(memgem)() and mq.TLO.Me.Gem(memgem).Name() == rankname end)
        mq.TLO.Window('SpellBookWnd').DoClose()
        memspell = nil
        memgem = 0
    end
    mq.delay(20)
end
