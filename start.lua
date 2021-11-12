--- @type mq
local mq = require 'mq'
--- @type ImGui
require 'ImGui'
local LIP = require 'ma.LIP'
local schema = require 'ma.schemas.ma'

local version = '0.5.3'

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
local selectedDebug = 'all' -- debug dropdown menu selection
local selectedSharedList = nil -- shared lists table selected list
local selectedSharedListItem = nil -- shared lists list table selected entry

local macroSchema = 'ma'
local INI_PATTERNS = {
    ['ma'] = {
        ['level'] = 'MuleAssist_%s_%s_%d.ini',
        ['nolevel'] = 'MuleAssist_%s_%s.ini'
    },
    ['ka'] = {
        ['nolevel'] = 'KissAssist_%s.ini'
    }
}
local StartCommand = {
    ['ma'] = '/mac muleassist assist ${Group.MainAssist}',
    ['ka'] = '/mac kissassist assist ${Group.MainAssist}'
}
local INIFile = nil -- file name of character INI to load
local INIFileContents = nil -- raw file contents for raw INI tab
local config = nil -- lua table version of INI content
local myServer = mq.TLO.EverQuest.Server()
local myName = mq.TLO.Me.CleanName()
local myLevel = mq.TLO.Me.Level()
local myClass = mq.TLO.Me.Class.ShortName():lower()

-- Storage for spell/AA/disc picker
local spells, altAbilities, discs = {categories={}},{},{}

local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.Hideable, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.BordersOuter)
local LEMONS_INFO_INI = mq.configDir..'/Lemons_Info.ini'
local MA_LISTS = {'FireMobs','ColdMobs','MagicMobs','PoisonMobs','DiseaseMobs','SlowMobs'}

local lemons_info = {}
local DEBUG = {all=false,dps=false,heal=false,buff=false,cast=false,combat=false,move=false,mez=false,pet=false,pull=false,chain=false,target=false}
local debugCaptureTime = '60'

-- Helper functions
local function printf(...)
    print(string.format(...))
end

local function Split(input, sep, limit, bRegexp)
    assert(sep ~= '')
    assert(limit == nil or limit >= 1)

    local aRecord = {}

    if input:len() > 0 then
        local bPlain = not bRegexp
        limit = limit or -1

        local nField, nStart = 1, 1
        local nFirst,nLast = input:find(sep, nStart, bPlain)
        while nFirst and limit ~= 0 do
            aRecord[nField] = input:sub(nStart, nFirst-1)
            nField = nField+1
            nStart = nLast+1
            nFirst,nLast = input:find(sep, nStart, bPlain)
            limit = limit-1
        end
        aRecord[nField] = input:sub(nStart)
    end

    return aRecord
end

local function ReadRawINIFile()
    local f = io.open(mq.configDir..'/'..INIFile, 'r')
    local contents = f:read('*a')
    io.close(f)
    return contents
end

local function WriteRawINIFile(contents)
    local f = io.open(mq.configDir..'/'..INIFile, 'w')
    f:write(contents)
    io.close(f)
end

local function FileExists(path)
    local f = io.open(path, "r")
    if f ~= nil then io.close(f) return true else return false end
end

local function CopyFile(source, dest)
    local f = io.open(source, 'r')
    local contents = f:read('*a')
    io.close(f)
    f = io.open(dest, 'w')
    f:write(contents)
    io.close(f)
end

local function FindINIFile()
    if macroSchema == 'ma' then
        if FileExists(mq.configDir..'/'..INI_PATTERNS[macroSchema]['level']:format(myServer, myName, myLevel)) then
            return INI_PATTERNS[macroSchema]['level']:format(myServer, myName, myLevel)
        elseif FileExists(mq.configDir..'/'..INI_PATTERNS[macroSchema]['nolevel']:format(myServer, myName)) then
            return INI_PATTERNS[macroSchema]['nolevel']:format(myServer, myName)
        else
            local fileLevel = myLevel-1
            repeat
                local fileName = INI_PATTERNS[macroSchema]['level']:format(myServer, myName, fileLevel)
                if FileExists(mq.configDir..'/'..fileName) then
                    local targetFileName = INI_PATTERNS[macroSchema]['level']:format(myServer, myName, myLevel)
                    CopyFile(mq.configDir..'/'..fileName, mq.configDir..'/'..targetFileName)
                    printf('Copying %s to %s', fileName, targetFileName)
                    return targetFileName
                end
                fileLevel = fileLevel-1
            until fileLevel == myLevel-10
        end
    elseif macroSchema == 'ka' then
        if FileExists(mq.configDir..'/'..INI_PATTERNS[macroSchema]['nolevel']:format(myName)) then
            return INI_PATTERNS[macroSchema]['nolevel']:format(myName)
        end
    end
end

local function HelpMarker(desc)
    ImGui.TextDisabled('(?)')
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
        ImGui.Text(desc)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

-- convert INI 0/1 to true/false for ImGui checkboxes
local function InitCheckBoxValue(value)
    if value then
        if type(value) == 'boolean' then return value end
        if type(value) == 'number' then return value ~= 0 end
        if type(value) == 'string' and value:upper() == 'TRUE' then return true else return false end
    else
        return false
    end
end

local function Save()
    -- Set "NULL" string values to nil so they aren't saved
    for sectionName,sectionProperties in pairs(config) do
        for key,value in pairs(sectionProperties) do
            if value == 'NULL' then
                -- Replace and XYZCond#=FALSE with nil as well if no corresponding XYZ# value
                local word = string.match(key, '[^%d]+')
                local number = string.match(key, '%d+')
                if number then
                    config[sectionName][word..'Cond'..number] = nil
                end
                config[sectionName][key] = nil
            end
        end
    end
    LIP.save(mq.configDir..'/'..INIFile, config, schema)
end

-- Ability menu initializers
local function InitSpellTree()
    -- Sort spells by level
    local SpellSorter = function(a, b)
        if mq.TLO.Spell(a).Level() < mq.TLO.Spell(b).Level() then
            return false
        elseif mq.TLO.Spell(b).Level() < mq.TLO.Spell(a).Level() then
            return true
        else
            return false
        end
    end
    -- Build spell tree for picking spells
    for spellIter=1,960 do
        local spell = mq.TLO.Me.Book(spellIter)
        if spell() then
            if not spells[spell.Category()] then
                spells[spell.Category()] = {subcategories={}}
                table.insert(spells.categories, spell.Category())
            end
            if not spells[spell.Category()][spell.Subcategory()] then
                spells[spell.Category()][spell.Subcategory()] = {}
                table.insert(spells[spell.Category()].subcategories, spell.Subcategory())
            end
            if spell.Level() >= myLevel-30 then
                local name = spell.Name():gsub(' Rk%..*', '')
                table.insert(spells[spell.Category()][spell.Subcategory()], name)
            end
        end
    end
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

-- Recreate the spell bar context menu
-- sectionName+key+index defines where to store the result
-- selectedIdx is used to clear spell upgrade input incase of updating over an existing entry
local function DrawSpellPicker(sectionName, key, index)
    if not config[sectionName][key..index] then
        config[sectionName][key..index] = ''
    end
    local valueParts = Split(config[sectionName][key..index],'|',1)
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
                                    local spellLevel = mq.TLO.Spell(spell).Level()
                                    SetSpellTextColor(spell)
                                    if ImGui.MenuItem(spellLevel..' - '..spell..'##'..sectionName..key..subcategory) then
                                        valueParts[1] = spell
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
        ImGui.EndPopup()
    end
    config[sectionName][key..index] = table.concat(valueParts, '|')
    if config[sectionName][key..index] == '|' then
        config[sectionName][key..index] = 'NULL'
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

local function CheckInputType(key, value, typestring, inputtype)
    if type(value) ~= typestring then
        printf('\arWARNING [%s]: %s value is not a %s: type=%s value=%s\a-x', key, inputtype, typestring, type(value), tostring(value))
    end
end

local function DrawKeyAndInputText(keyText, label, value, helpText)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(keyText)
    ImGui.PopStyleColor()
    ImGui.SameLine()
    HelpMarker(helpText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(175)
    -- the first part, spell/item/disc name, /command, etc
    CheckInputType(label, value, 'string', 'InputText')
    return ImGui.InputText(label, value)
end

-- Draw the value and condition of the selected list item
local function DrawSelectedListItem(sectionName, key, value)
    local valueKey = key..selectedListItem[2]
    -- make sure values not nil so imgui inputs don't barf
    if config[sectionName][valueKey] == nil then
        config[sectionName][valueKey] = 'NULL'
    end
    -- split the value so we can update spell name and stuff after the | individually
    local valueParts = Split(config[sectionName][valueKey], '|', 1)
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
        if config[sectionName][valueCondKey] == nil then
            config[sectionName][valueCondKey] = 'NULL'
        end
        config[sectionName][valueCondKey] = DrawKeyAndInputText('Conditions: ', '##cond'..sectionName..valueKey, config[sectionName][valueCondKey], value['CondTooltip'])
    end
    local spell = mq.TLO.Spell(valueParts[1])
    if mq.TLO.Me.Book(spell.RankName())() then
        local upgradeResult = DrawSelectedSpellUpgradeButton(spell)
        if upgradeResult then valueParts[1] = upgradeResult end
    end
    if valueParts[1] and string.len(valueParts[1]) > 0 then
        config[sectionName][valueKey] = valueParts[1]
        if valueParts[2] and string.len(valueParts[2]) > 0 then
            config[sectionName][valueKey] = config[sectionName][valueKey]..'|'..valueParts[2]:gsub('|$','')
        end
    else
        config[sectionName][valueKey] = ''
    end
    ImGui.Separator()
end

local function DrawPlainListButton(sectionName, key, listIdx, iconSize)
    -- INI value is set to non-spell/item
    if ImGui.Button(listIdx..'##'..sectionName..key, iconSize[1], iconSize[2]) and type(listIdx) == 'number' then
        selectedListItem = {key, listIdx}
        selectedUpgrade = nil
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
    if config[sectionName][key..index] and config[sectionName][key..index] ~= 'NULL' then
        iniValue = Split(config[sectionName][key..index],'|',1)[1]
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
            local spellIcon = mq.TLO.Spell(iniValue).SpellIcon()
            animSpellIcons:SetTextureCell(spellIcon)
            ImGui.DrawTextureAnimation(animSpellIcons, iconSize[1], iconSize[2])
        elseif mq.TLO.FindItem(iniValue)() then
            local itemIcon = mq.TLO.FindItem(iniValue).Icon()
            animItems:SetTextureCell(itemIcon-500)
            ImGui.DrawTextureAnimation(animItems, iconSize[1], iconSize[2])
        else
            DrawPlainListButton(sectionName, key, index, iconSize)
        end
        DrawTooltip(iniValue)
        -- Handle clicks on spell icon animations that aren't buttons
        if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) and type(index) == 'number' then
            selectedListItem = {key, index}
            selectedUpgrade = nil
        end
        -- Spell picker context menu on right click button
        DrawSpellPicker(sectionName, key, index)
    else
        -- No INI value assigned yet for this key
        DrawPlainListButton(sectionName, key, index, iconSize)
        DrawSpellPicker(sectionName, key, index)
    end
end

-- Draw 0..N buttons based on value of XYZSize input
local function DrawList(sectionName, key, value)
    ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    ImGui.Text(key..'Size: ')
    ImGui.PopStyleColor()
    ImGui.SameLine()
    HelpMarker(value['SizeTooltip'])
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    local size = config[sectionName][key..'Size']
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
    local _,yOffset = ImGui.GetCursorPos()
    local avail = ImGui.GetContentRegionAvail()
    local iconsPerRow = math.floor(avail/38)
    if iconsPerRow == 0 then iconsPerRow = 1 end
    for i=1,size do
        local offsetMod = math.floor((i-1)/iconsPerRow)
        ImGui.SetCursorPosY(yOffset+(34*offsetMod))
        DrawSpellIconOrButton(sectionName, key, i)
        if i%iconsPerRow ~= 0 and i < size then
            ImGui.SameLine()
        end
    end
    config[sectionName][key..'Size'] = size
end

local function DrawMultiPartProperty(sectionName, key, value)
    -- TODO: what's a nice clean way to represent values which are multiple parts? 
    -- Currently just using this experimentally with RezAcceptOn
    local parts = Split(config[sectionName][key], '|',1)
    for partIdx,part in ipairs(value['Parts']) do
        if part['Type'] == 'SWITCH' then
            ImGui.Text(part['Name']..': ')
            ImGui.SameLine()
            local value = InitCheckBoxValue(tonumber(parts[partIdx]))
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
        config[sectionName][key] = table.concat(parts, '|')
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
    HelpMarker(value['Tooltip'])
    ImGui.SameLine()
    if config[sectionName][key] == nil then
        config[sectionName][key] = 'NULL'
    end
    ImGui.SetCursorPosX(175)
    if value['Type'] == 'SWITCH' then
        local initialValue = InitCheckBoxValue(config[sectionName][key])
        CheckInputType(key, initialValue, 'boolean', 'Checkbox')
        config[sectionName][key] = ImGui.Checkbox('##'..key, initialValue)
    elseif value['Type'] == 'SPELL' then
        DrawSpellIconOrButton(sectionName, key, '')
        ImGui.SameLine()
        ImGui.PushItemWidth(350)
        local initialValue = config[sectionName][key]
        CheckInputType(key, initialValue, 'string', 'InputText')
        config[sectionName][key] = ImGui.InputText('##textinput'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
    elseif value['Type'] == 'NUMBER' then
        local initialValue = config[sectionName][key]
        if not initialValue or initialValue == 'NULL' or type(initialValue) ~= 'number' then
            CheckInputType(key, initialValue, 'number', 'InputInt')
            initialValue = 0
        end
        ImGui.PushItemWidth(350)
        config[sectionName][key] = ImGui.InputInt('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
        if value['Min'] and config[sectionName][key] < value['Min'] then
            config[sectionName][key] = value['Min']
        elseif value['Max'] and config[sectionName][key] > value['Max'] then
            config[sectionName][key] = value['Max']
        end
    elseif value['Type'] == 'STRING' then
        ImGui.PushItemWidth(350)
        local initialValue = tostring(config[sectionName][key])
        CheckInputType(key, initialValue, 'string', 'InputText')
        config[sectionName][key] = ImGui.InputText('##'..sectionName..key, initialValue)
        ImGui.PopItemWidth()
    elseif value['Type'] == 'MULTIPART' then
        DrawMultiPartProperty(sectionName, key, value)
    end
end

-- Draw main On/Off switches for an INI section
local function DrawSectionControlSwitches(sectionName, sectionProperties)
    if sectionProperties['On'] then
        if sectionProperties['On']['Type'] == 'SWITCH' then
            local value = InitCheckBoxValue(config[sectionName][sectionName..'On'])
            CheckInputType(sectionName..'On', value, 'boolean', 'Checkbox')
            config[sectionName][sectionName..'On'] = ImGui.Checkbox(sectionName..'On', value)
        elseif sectionProperties['On']['Type'] == 'NUMBER' then
            -- Type=NUMBER control switch mostly a special case for DPS section only
            if not config[sectionName][sectionName..'On'] then config[sectionName][sectionName..'On'] = 0 end
            ImGui.PushItemWidth(100)
            config[sectionName][sectionName..'On'] = ImGui.InputInt(sectionName..'On', config[sectionName][sectionName..'On'])
            ImGui.PopItemWidth()
            if sectionProperties['On']['Min'] and config[sectionName][sectionName..'On'] < sectionProperties['On']['Min'] then
                config[sectionName][sectionName..'On'] = sectionProperties['On']['Min']
            elseif sectionProperties['On']['Max'] and config[sectionName][sectionName..'On'] > sectionProperties['On']['Max'] then
                config[sectionName][sectionName..'On'] = sectionProperties['On']['Max']
            end
        end
        if sectionProperties['COn'] then ImGui.SameLine() end
    end
    if sectionProperties['COn'] then
        config[sectionName][sectionName..'COn'] = ImGui.Checkbox(sectionName..'COn', InitCheckBoxValue(config[sectionName][sectionName..'COn']))
    end
    ImGui.Separator()
end

local function DrawMySpellsGemList()
    local _,yOffset = ImGui.GetCursorPos()
    local avail = ImGui.GetContentRegionAvail()
    local iconsPerRow = math.floor(avail/36)
    if iconsPerRow == 0 then iconsPerRow = 1 end
    for i=1,13 do
        local offsetMod = math.floor((i-1)/iconsPerRow)
        ImGui.SetCursorPosY(yOffset+(34*offsetMod))
        DrawSpellIconOrButton('MySpells', 'Gem', i)
        if i%iconsPerRow ~= 0 and i < 13 then
            ImGui.SameLine()
        end
    end
end

local function DrawMySpells()
    ImGui.TextColored(1, 1, 0, 1, 'MySpells:')
    if config['MySpells'] then
        DrawMySpellsGemList()
    end
    if ImGui.Button('Update from spell bar') then
        if not config['MySpells'] then config['MySpells'] = {} end
        for i=1,13 do
            config['MySpells']['Gem'..i] = mq.TLO.Me.Gem(i).Name()
        end
        Save()
        INIFileContents = ReadRawINIFile()
    end
end

-- Draw an INI section tab
local function DrawSection(sectionName, sectionProperties)
    if not config[sectionName] then
        config[sectionName] = {}
    end
    -- Draw main section control switches first
    if sectionProperties['Controls'] then
        DrawSectionControlSwitches(sectionName, sectionProperties['Controls'])
    end
    if ImGui.BeginChild('SectionProperties') then
        if sectionName == 'SpellSet' then
            -- special case for SpellSet tab to draw save spell set button
            DrawMySpells()
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

local function DrawRawINIEditTab()
    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
        if FileExists(mq.configDir..'/'..INIFile) then
            INIFileContents = ReadRawINIFile()
        end
    end
    if ImGui.Button('Refresh Raw INI##rawini') then
        if FileExists(mq.configDir..'/'..INIFile) then
            INIFileContents = ReadRawINIFile()
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Save Raw INI##rawini') then
        WriteRawINIFile(INIFileContents)
        config = LIP.load(mq.configDir..'/'..INIFile)
    end
    local x,y = ImGui.GetContentRegionAvail()
    INIFileContents,_ = ImGui.InputTextMultiline("##rawinput", INIFileContents or '', x-15, y-15, ImGuiInputTextFlags.None)
end

local function DrawListsTab()
    ImGui.PushTextWrapPos(ImGui.GetContentRegionAvail()-10)
    ImGui.TextColored(0, 1, 1, 1, "View shared list content from Lemons_Info.ini. To add entries, use the macro /addxyz commands and click reload.")
    ImGui.PopTextWrapPos()
    ImGui.Text('Select a list below to edit:')
    ImGui.SameLine()
    if ImGui.SmallButton('Save Lemons INI') then
        LIP.save(LEMONS_INFO_INI, lemons_info, schema)
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Reload Lemons INI') then
        if FileExists(LEMONS_INFO_INI) then
            lemons_info = LIP.load(LEMONS_INFO_INI, true)
        end
    end
    if ImGui.BeginTable('ListSelectionTable', 1, TABLE_FLAGS, 0, 150, 0.0) then
        ImGui.TableSetupColumn('List Name',     0,   -1.0, 1)
        ImGui.TableSetupScrollFreeze(0, 1) -- Make row always visible
        ImGui.TableHeadersRow()
        local clipper = ImGuiListClipper.new()
        clipper:Begin(#MA_LISTS)
        while clipper:Step() do
            for row_n = clipper.DisplayStart, clipper.DisplayEnd - 1, 1 do
                local clipName = MA_LISTS[row_n+1]
                ImGui.PushID(clipName)
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                local sel = ImGui.Selectable(clipName, selectedSharedList == clipName)
                if sel then
                    selectedSharedList = clipName
                end
                ImGui.PopID()
            end
        end
        ImGui.EndTable()
    end
    if selectedSharedList ~= nil then
        ImGui.TextColored(1, 1, 0, 1, selectedSharedList)
        ImGui.SameLine()
        ImGui.SetCursorPosX(100)
        ImGui.SameLine()
        if ImGui.SmallButton('Remove Selected') then
            lemons_info[selectedSharedList][selectedSharedListItem] = nil
        end
        if ImGui.BeginTable('SelectedListTable', 1, TABLE_FLAGS, 0, 0, 0.0) then
            ImGui.TableSetupColumn('Mob or Zone Short Name',     0,   -1.0, 1)
            ImGui.TableSetupScrollFreeze(0, 1) -- Make row always visible
            ImGui.TableHeadersRow()
            if lemons_info[selectedSharedList] then
                for key,_ in pairs(lemons_info[selectedSharedList]) do
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    local sel = ImGui.Selectable(key, selectedSharedListItem == key)
                    if sel then
                        selectedSharedListItem = key
                    end
                end
            end
            ImGui.EndTable()
        end
    end
end

local function DrawDebugTab()
    local debuginput = ''
    for i,j in pairs(DEBUG) do
        if j then debuginput = debuginput..i end
    end
    if ImGui.BeginCombo('Debug Categories', debuginput) then
        for i,j in pairs(DEBUG) do
            DEBUG[i] = ImGui.Checkbox(i, j)
        end
        ImGui.EndCombo()
    end
    debugCaptureTime = ImGui.InputText('Debug Capture Time', debugCaptureTime)
    if selectedDebug then
        if ImGui.Button('Enable Debug') then
            debuginput = ''
            for i,j in pairs(DEBUG) do
                if j then debuginput = debuginput..i end
            end
            mq.cmdf('/writedebug %s %s', debuginput, debugCaptureTime)
        end
    end
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

-- Define this down here since the functions need to be defined first
local customSections = {
    ['ma'] = {['Raw INI']=DrawRawINIEditTab, ['Shared Lists']=DrawListsTab, ['Debug']=DrawDebugTab},
    ['ka'] = {['Raw INI']=DrawRawINIEditTab}
}

local function LeftPaneWindow()
    local x,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("left", leftPanelWidth, y-1, true) then
        if ImGui.BeginTable('SelectSectionTable', 1, TABLE_FLAGS, 0, 0, 0.0) then
            ImGui.TableSetupColumn('Section Name',     0,   -1.0, 1)
            ImGui.TableSetupScrollFreeze(0, 1) -- Make row always visible
            ImGui.TableHeadersRow()

            for _,sectionName in ipairs(schema.Sections) do
                if schema[sectionName] and (not schema[sectionName].Classes or schema[sectionName].Classes[myClass]) then
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    local popStyleColor = false
                    if schema[sectionName]['Controls'] and schema[sectionName]['Controls']['On'] then
                        if not config[sectionName] or not config[sectionName][sectionName..'On'] or config[sectionName][sectionName..'On'] == 0 then
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
            for section,_ in pairs(customSections[macroSchema]) do
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
        if customSections[macroSchema][selectedSection] then
            customSections[macroSchema][selectedSection]()
        else
            DrawSection(selectedSection, schema[selectedSection])
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

local function SetMAVars()
    schema = require 'ma.schemas.ma'
    INIFile = FindINIFile()
    if INIFile then
        config = LIP.load(mq.configDir..'/'..INIFile)
        INIFileContents = ReadRawINIFile()
    else
        INIFile = INI_PATTERNS['ma']['level']:format(myServer, myName, myLevel)
        config = {}
    end
end

local function SetKAVars()
    schema = require 'ma.schemas.ka'
    INIFile = FindINIFile()
    if INIFile then
        config = LIP.load(mq.configDir..'/'..INIFile)
        INIFileContents = ReadRawINIFile()
    else
        INIFile = INI_PATTERNS['ka']['nolevel']:format(myName)
        config = {}
    end
end

local radioValue = 1
local function DrawWindowHeaderSettings()
    radioValue,_ = ImGui.RadioButton("MuleAssist", radioValue, 1)
    ImGui.SameLine()
    radioValue,_ = ImGui.RadioButton("KissAssist", radioValue, 2)
    if radioValue == 1 then
        if macroSchema ~= 'ma' then
            print('ma selected')
            macroSchema = 'ma'
            SetMAVars()
        end
    elseif radioValue == 2 then
        if macroSchema ~= 'ka' then
            print('ka selected')
            macroSchema = 'ka'
            SetKAVars()
        end
    end
    ImGui.Separator()

    ImGui.Text('INI File: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    ImGui.PushItemWidth(350)
    INIFile,_ = ImGui.InputText('##INIInput', INIFile)
    ImGui.SameLine()
    if ImGui.Button('Save INI') then
        Save()
        INIFileContents = ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Reload INI') then
        config = LIP.load(mq.configDir..'/'..INIFile)
    end
    --[[
    ImGui.SameLine()
    if ImGui.BeginCombo('Macro', macroSchema) then
        if ImGui.Selectable('ma', macroSchema == 'ma') then
            if macroSchema ~= 'ma' then
                print('ma selected')
                macroSchema = 'ma'
                SetMAVars()
            end
        end
        if ImGui.Selectable('ka', macroSchema == 'ka') then
            if macroSchema ~= 'ka' then
                print('ka selected')
                macroSchema = 'ka'
                SetKAVars()
            end
        end
        ImGui.EndCombo()
    end
    --]]
    ImGui.Separator()
    ImGui.Text('Start Command: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(120)
    ImGui.PushItemWidth(350)
    StartCommand[macroSchema],_ = ImGui.InputText('##StartCommand', StartCommand[macroSchema])
    ImGui.SameLine()
    if ImGui.Button('Start Macro') then
        mq.cmd(StartCommand[macroSchema])
    end
    ImGui.Separator()
end

local MAUI = function()
    open, shouldDrawUI = ImGui.Begin('MAUI (v'..version..')###MuleAssist', open)
    if shouldDrawUI then
        -- these appear to be the numbers for the window on first use... probably shouldn't rely on them.
        if initialRun then
            if ImGui.GetWindowHeight() == 38 and ImGui.GetWindowWidth() == 32 then
                ImGui.SetWindowSize(727,487)
            end
            initialRun = false
        end
        DrawWindowHeaderSettings()
        DrawWindowPanels()
    end
    ImGui.End()
    if not open then terminate = true end
end

-- Load INI into table as well as raw content
--INIFile = FindINIFileName()
INIFile = FindINIFile()
if INIFile then
    config = LIP.load(mq.configDir..'/'..INIFile)
    INIFileContents = ReadRawINIFile()
else
    INIFile = INI_PATTERNS['ma']['level']:format(myServer, myName, myLevel)
    config = {}
end
if FileExists(LEMONS_INFO_INI) then
    lemons_info = LIP.load(LEMONS_INFO_INI, true)
end

local initCo = coroutine.create(function()
    -- Initializing and sorting spell tree takes a few seconds, so run in parallel
    InitSpellTree()
    InitAATree()
    InitDiscTree()
end)
coroutine.resume(initCo)

mq.imgui.init('MuleAssist', MAUI)

while not terminate do
    if coroutine.status(initCo) == 'suspended' then
        coroutine.resume(initCo)
    end
    mq.delay(20)
end
