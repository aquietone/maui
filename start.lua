local mq = require 'mq'
require 'ImGui'
local LIP = require 'ma.LIP'
local schema = require 'ma.schema'

-- Animations for drawing spell/item icons
local animSpellIcons = mq.FindTextureAnimation('A_SpellIcons')
local animItems = mq.FindTextureAnimation('A_DragItem')

local open = true
local shouldDrawUI = true
local terminate = false
-- Some sections (just buffs atm) have more than 1 list property. Using a single 'selected'
-- value for the selected list item would interfere when multiple lists are displayed.
-- So, set individual selected items for up to 5 list properties in a section.
local selected = {0,0,0,0,0}
local selectedUpgrade = {}

local StartCommand = '/mac muleassist assist ${Group.MainAssist}'
local INIFile = nil
local INIFileContents = nil
local config = nil
local myServer = mq.TLO.EverQuest.Server()
local myName = mq.TLO.Me.CleanName()
local myLevel = mq.TLO.Me.Level()
local myClass = mq.TLO.Me.Class.ShortName():lower()

-- Storage for spell/AA/disc picker
local spellIter, aaIter, discIter = 1,1,1
local spells, altAbilities, discs = {categories={}},{},{}

-- Helper functions
local Split = function(input, sep)
    if sep == nil then
        sep = "|"
    end
    local t={}
    for str in string.gmatch(input, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local ReadRawINIFile = function()
    local f = io.open(mq.configDir..'\\'..INIFile, 'r')
    local contents = f:read('*a')
    io.close(f)
    return contents
end

local WriteRawINIFile = function(contents)
    local f = io.open(mq.configDir..'\\'..INIFile, 'w')
    f:write(contents)
    io.close(f)
end

local FileExists = function(path)
    local f = io.open(path, "r")
    if f ~= nil then io.close(f) return true else return false end
end

local FindINIFileName = function()
    if FileExists(mq.configDir..'\\'..string.format('MuleAssist_%s_%s_%d.ini', myServer, myName, myLevel)) then
        return string.format('MuleAssist_%s_%s_%d.ini', myServer, myName, myLevel)
    elseif FileExists(mq.configDir..'\\'..string.format('MuleAssist_%s_%s.ini', myServer, myName)) then
        return string.format('MuleAssist_%s_%s.ini', myServer, myName)
    else
        local fileLevel = myLevel-1
        repeat
            if FileExists(mq.configDir..'\\'..string.format('MuleAssist_%s_%s_%d.ini', myServer, myName, fileLevel)) then
                return string.format('MuleAssist_%s_%s_%d.ini', myServer, myName, fileLevel)
            end
            fileLevel = fileLevel-1
        until fileLevel == myLevel-10
    end
    return nil
end

-- Ability menu initializers
local InitSpellTree = function()
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

local InitAATree = function()
    -- TODO: what's the right way to loop through activated abilities?
    for aaIter=1,10000 do
        if mq.TLO.Me.AltAbility(aaIter)() and mq.TLO.Me.AltAbility(aaIter).Spell() then
            table.insert(altAbilities, mq.TLO.Me.AltAbility(aaIter).Name())
        end
        aaIter = aaIter + 1
    end
    table.sort(altAbilities)
end

local InitDiscTree = function()
    -- Build disc tree for picking discs
    -- TODO: split up by timers? haven't really looked at discs yet
    repeat
        local name = mq.TLO.Me.CombatAbility(discIter).Name():gsub(' Rk%..*', '')
        table.insert(discs, name)
        discIter = discIter + 1
    until mq.TLO.Me.CombatAbility(discIter)() == nil
    table.sort(discs)
end

--Given some spell data input, determine whether a better spell with the same inputs exists
local GetSpellUpgrade = function(targetType, subCat, numEffects, minLevel)
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
local SetSpellTextColor = function(spell)
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
local DrawSpellPicker = function(sectionName, key, index, selectedIdx)
    if not config[sectionName][key..index] then
        config[sectionName][key..index] = ''
    end
    local valueParts = Split(config[sectionName][key..index])
    -- Right click context menu popup on list buttons
    if ImGui.BeginPopupContextItem('##rcmenu'..sectionName..key..index) then
        -- Top level 'Spells' menu item
        if ImGui.BeginMenu('Spells##rcmenu'..sectionName..key) then
            for _,category in ipairs(spells.categories) do
                -- Spell Subcategories submenu
                if ImGui.BeginMenu(category..'##rcmenu'..sectionName..key..category) then
                    for _,subcategory in ipairs(spells[category].subcategories) do
                        -- Subcategory Spell menu
                        if ImGui.BeginMenu(subcategory..'##'..sectionName..key..subcategory) then
                            for _,spell in ipairs(spells[category][subcategory]) do
                                local spellLevel = mq.TLO.Spell(spell).Level()
                                SetSpellTextColor(spell)
                                if ImGui.MenuItem(spellLevel..' - '..spell..'##'..sectionName..key..subcategory) then
                                    valueParts[1] = spell
                                    selectedUpgrade[selectedIdx] = nil
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
        -- Top level 'AAs' menu item
        if ImGui.BeginMenu('AAs##rcmenu'..sectionName..key) then
            for _,altAbility in ipairs(altAbilities) do
                if ImGui.MenuItem(altAbility..'##aa'..sectionName..key) then
                    valueParts[1] = altAbility
                end
            end
            ImGui.EndMenu()
        end
        -- Top level 'Discs' menu item
        if ImGui.BeginMenu('Combat Abilities##rcmenu'..sectionName..key) then
            for _,disc in ipairs(discs) do
                if ImGui.MenuItem(disc..'##disc'..sectionName..key) then
                    valueParts[1] = disc
                end
            end
            ImGui.EndMenu()
        end
        ImGui.EndPopup()
    end
    config[sectionName][key..index] = table.concat(valueParts, '|')
    if config[sectionName][key..index] == '|' then
        config[sectionName][key..index] = 'NULL'
    end
end

-- Draw the value and condition of the selected list item
local DrawSelectedListItem = function(sectionName, key, value, selectedIdx)
    local valueKey = key..selected[selectedIdx]
    local valueCondKey = key..'Cond'..selected[selectedIdx]
    -- make sure values not nil so imgui inputs don't barf
    if config[sectionName][valueKey] == nil then
        config[sectionName][valueKey] = 'NULL'
    end
    -- split the value so we can update spell name and stuff after the | individually
    local valueParts = Split(config[sectionName][valueKey])
    if not valueParts[1] then valueParts[1] = '' end
    if not valueParts[2] then valueParts[2] = '' end

    ImGui.Separator()
    ImGui.Text(string.format('%s.%s%d', sectionName, key, selected[selectedIdx]))
    ImGui.Text('Value: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(175)
    -- the first part, spell/item/disc name, /command, etc
    valueParts[1] = ImGui.InputText('##'..sectionName..valueKey, valueParts[1])
    ImGui.Text('Options: ')
    ImGui.SameLine()
    ImGui.SetCursorPosX(175)
    -- the rest of the stuff after the first |, classes, percents, oog, etc
    valueParts[2] = ImGui.InputText('##'..sectionName..valueKey..'options', valueParts[2])
    if value['Conditions'] then
        ImGui.Text('Condition: ')
        ImGui.SameLine()
        if config[sectionName][valueCondKey] == nil then
            config[sectionName][valueCondKey] = 'NULL'
        end
        ImGui.SetCursorPosX(175)
        config[sectionName][valueCondKey] = ImGui.InputText('##cond'..sectionName..valueKey, config[sectionName][valueCondKey])
    end
    -- TODO: There's probably better ways to handle finding and displaying the upgrade spell button...
    local spell = mq.TLO.Spell(valueParts[1])
    if spell() then
        -- Avoid finding the upgrade more than once
        if not selectedUpgrade[selectedIdx] then
            selectedUpgrade[selectedIdx] = GetSpellUpgrade(spell.TargetType(), spell.Subcategory(), spell.NumEffects(), spell.Level())
        end
        -- Upgrade found? display the upgrade button
        if selectedUpgrade[selectedIdx] ~= '' and selectedUpgrade[selectedIdx] ~= spell.Name() then
            if ImGui.Button('Upgrade Available - '..selectedUpgrade[selectedIdx]) then
                valueParts[1] = selectedUpgrade[selectedIdx]
                selectedUpgrade[selectedIdx] = nil
            end
        end
    end
    config[sectionName][valueKey] = table.concat(valueParts, '|')
    if config[sectionName][valueKey] == '|' then
        config[sectionName][valueKey] = ''
    end
    config[sectionName][valueKey] = config[sectionName][valueKey]:gsub('|$','')
    ImGui.Separator()
end

local DrawSpellIconOrButton = function(sectionName, key, index, selectedIdx)
    local iniValue = config[sectionName][key..index]
    if iniValue and iniValue ~= 'NULL' then
        local iniValueParts = Split(iniValue,'|')
        -- Use first part of INI value as spell or item name to lookup icon
        if mq.TLO.Spell(iniValueParts[1])() then
            local spellIcon = mq.TLO.Spell(iniValueParts[1]).SpellIcon()
            animSpellIcons:SetTextureCell(spellIcon)
            ImGui.DrawTextureAnimation(animSpellIcons, 30, 30)
        elseif mq.TLO.FindItem(iniValueParts[1])() then
            local itemIcon = mq.TLO.FindItem(iniValueParts[1]).Icon()
            animItems:SetTextureCell(itemIcon-500)
            ImGui.DrawTextureAnimation(animItems, 30, 30)
        else
            -- INI value is set to non-spell/item
            if ImGui.Button(index..'##'..sectionName..key, 30, 30) then
                if selectedIdx >= 0 then
                    selected[selectedIdx] = index
                    selectedUpgrade[selectedIdx] = nil
                end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
            ImGui.Text(iniValueParts[1])
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        -- Handle clicks on spell icon animations that aren't buttons
        if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
            if selectedIdx >= 0 then 
                selected[selectedIdx] = index
                selectedUpgrade[selectedIdx] = nil
            end
        end
        -- Spell picker context menu on right click button
        DrawSpellPicker(sectionName, key, index, selectedIdx)
    else
        if ImGui.Button(index..'##'..sectionName..key, 30, 30) then
            if selectedIdx >= 0 then
                selected[selectedIdx] = index
                selectedUpgrade[selectedIdx] = nil
            end
        end
        DrawSpellPicker(sectionName, key, index, selectedIdx)
    end
end

-- Draw 0..N buttons based on value of XYZSize input
local DrawList = function(sectionName, key, value, selectedIdx)
    ImGui.Text(key..'Size: ')
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    if config[sectionName][key..'Size'] == nil then
        config[sectionName][key..'Size'] = 1
    end
    ImGui.SetCursorPosX(175)
    -- Set size of list and check boundaries
    config[sectionName][key..'Size'] = ImGui.InputInt('##sizeinput'..sectionName..key, config[sectionName][key..'Size'])
    if config[sectionName][key..'Size'] < 0 then
        config[sectionName][key..'Size'] = 0
    elseif config[sectionName][key..'Size'] > value['Max'] then
        config[sectionName][key..'Size'] = value['Max']
    end
    if config[sectionName][key..'Size'] < selected[selectedIdx] then
        selected[selectedIdx] = 0
        selectedUpgrade[selectedIdx] = nil
    end
    ImGui.PopItemWidth()
    for i=1,config[sectionName][key..'Size'] do
        DrawSpellIconOrButton(sectionName, key, i, selectedIdx)
        if i%20 ~= 0 and i < config[sectionName][key..'Size'] then
            ImGui.SameLine()
        end
    end
    if selected[selectedIdx] > 0 then
        DrawSelectedListItem(sectionName, key, value, selectedIdx)
    end
end

-- convert INI 0/1 to true/false for ImGui checkboxes
local InitCheckBoxValue = function(value)
    if not value or value == 0 or value == 'NULL' then
        return false
    elseif value == 1 then
        return true
    end
    return value
end

-- Draw a generic section key/value property
local DrawProperty = function(sectionName, key, value)
    ImGui.Text(key..': ')
    ImGui.SameLine()
    if config[sectionName][key] == nil then
        config[sectionName][key] = 'NULL'
    end
    ImGui.SetCursorPosX(175)
    if value['Type'] == 'SWITCH' then
        config[sectionName][key] = ImGui.Checkbox('##'..key, InitCheckBoxValue(config[sectionName][key]))
    elseif value['Type'] == 'SPELL' then
        DrawSpellIconOrButton(sectionName, key, '', -1)
        ImGui.SameLine()
        ImGui.PushItemWidth(350)
        config[sectionName][key] = ImGui.InputText('##textinput'..sectionName..key, config[sectionName][key])
        ImGui.PopItemWidth()
    elseif value['Type'] == 'NUMBER' then
        if config[sectionName][key] == 'NULL' then config[sectionName][key] = 0 end
        ImGui.PushItemWidth(350)
        config[sectionName][key] = ImGui.InputInt('##'..sectionName..key, config[sectionName][key])
        ImGui.PopItemWidth()
        if value['Min'] and config[sectionName][key] < value['Min'] then
            config[sectionName][key] = value['Min']
        elseif value['Max'] and config[sectionName][key] > value['Max'] then
            config[sectionName][key] = value['Max']
        end
    elseif value['Type'] == 'STRING' then
        ImGui.PushItemWidth(350)
        config[sectionName][key] = ImGui.InputText('##'..sectionName..key, tostring(config[sectionName][key]))
        ImGui.PopItemWidth()
    elseif value['Type'] == 'MULTIPART' then
        -- TODO: what's a nice clean way to represent values which are multiple parts? 
        -- Currently just using this experimentally with RezAcceptOn
        local parts = Split(config[sectionName][key])
        for partIdx,part in ipairs(value['Parts']) do
            if part['Type'] == 'SWITCH' then
                ImGui.Text(part['Name']..': ')
                ImGui.SameLine()
                parts[partIdx] = ImGui.Checkbox('##'..key, InitCheckBoxValue(tonumber(parts[partIdx])))
                if parts[partIdx] then parts[partIdx] = '1' else parts[partIdx] = '0' end
            elseif part['Type'] == 'NUMBER' then
                if not parts[partIdx] or parts[partIdx] == 'NULL' then parts[partIdx] = 0 end
                ImGui.Text(part['Name']..': ')
                ImGui.SameLine()
                ImGui.PushItemWidth(100)
                parts[partIdx] = ImGui.InputInt('##'..sectionName..key..partIdx, tonumber(parts[partIdx]))
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
end

-- Draw main On/Off switches for an INI section
local DrawSectionControlSwitches = function(sectionName, sectionProperties)
    if sectionProperties['On'] then
        if sectionProperties['On']['Type'] == 'SWITCH' then
            config[sectionName][sectionName..'On'] = ImGui.Checkbox(sectionName..'On', InitCheckBoxValue(config[sectionName][sectionName..'On']))
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

-- Draw an INI section tab
local DrawSection = function(sectionName, sectionProperties)
    if not config[sectionName] then
        config[sectionName] = {}
    end
    -- Draw main section control switches first
    if sectionProperties['Controls'] then
        DrawSectionControlSwitches(sectionName, sectionProperties['Controls'])
    end
    if ImGui.BeginChild('sectionwindow') then
        -- Draw List properties before general properties
        local listIdx = 1
        for key,value in pairs(sectionProperties['Properties']) do
            if value['Type'] == 'LIST' then
                DrawList(sectionName, key, value, listIdx)
                listIdx = listIdx + 1
            end
        end
        -- Generic properties last
        for key,value in pairs(sectionProperties['Properties']) do
            if value['Type'] ~= 'LIST' then
                DrawProperty(sectionName, key, value)
            end
        end
        ImGui.EndChild()
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
    LIP.save(mq.configDir..'\\'..INIFile, config)
end

local DrawRawINIEditTab = function()
    if ImGui.BeginChild('rawiniwindow') then
        if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
            if FileExists(mq.configDir..'\\'..INIFile) then
                INIFileContents = ReadRawINIFile()
            end
        end
        if ImGui.Button('Refresh Raw INI##rawini') then
            if FileExists(mq.configDir..'\\'..INIFile) then
                INIFileContents = ReadRawINIFile()
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Save Raw INI##rawini') then
            WriteRawINIFile(INIFileContents)
            config = LIP.load(mq.configDir..'\\'..INIFile)
        end
        local x,y = ImGui.GetContentRegionAvail()
        INIFileContents,_ = ImGui.InputTextMultiline("##rawinput", INIFileContents or '', x-15, y-15, ImGuiInputTextFlags.None)
        ImGui.EndChild()
    end
    ImGui.EndTabItem()
end

local DrawWindowHeaderSettings = function()
    ImGui.Text('INI File: ')
    ImGui.SameLine()
    INIFile,_ = ImGui.InputText('##INIInput', INIFile)
    ImGui.SameLine()
    if ImGui.Button('Save INI') then
        Save()
        INIFileContents = ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Reload INI') then
        config = LIP.load(mq.configDir..'\\'..INIFile)
    end
    ImGui.Separator()
    ImGui.Text('Start Command: ')
    ImGui.SameLine()
    StartCommand,_ = ImGui.InputText('##StartCommand', StartCommand)
    ImGui.SameLine()
    if ImGui.Button('Start Macro') then
        mq.cmd(StartCommand)
    end
    ImGui.Separator()
end

local DrawWindowTabBar = function()
    if ImGui.BeginTabBar('Settings') then
        for sectionName,sectionProperties in pairs(schema) do
            if not schema[sectionName].Classes or schema[sectionName].Classes[myClass] then
                if ImGui.BeginTabItem(sectionName) then
                    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
                        selected = {0,0,0,0,0}
                    end
                    DrawSection(sectionName, sectionProperties)
                    ImGui.EndTabItem()
                end
            end
        end
        if ImGui.BeginTabItem('Raw') then
            DrawRawINIEditTab()
        end
    end
end

local MAUI = function()
    open, shouldDrawUI = ImGui.Begin('MuleAssist', open)
    if shouldDrawUI then
        DrawWindowHeaderSettings()
        DrawWindowTabBar()
        
        if not open then
            terminate = true
        end
    end
    ImGui.End()
end

-- Load INI into table as well as raw content
INIFile = FindINIFileName()
if INIFile then
    config = LIP.load(mq.configDir..'\\'..INIFile)
    INIFileContents = ReadRawINIFile()
else
    INIFile = string.format('MuleAssist_%s_%s_%d.ini', myServer, myName, myLevel)
    config = {}
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