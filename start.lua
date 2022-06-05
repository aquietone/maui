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
local selected = 0

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
local spells, altAbilities, discs = {},{},{}

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

-- ImGui functions

local DrawSpellPicker = function(sectionName, key, index)
    -- Right click context menu popup on list buttons
    if ImGui.BeginPopupContextItem('##rcmenu'..sectionName..key..index) then
        -- Top level 'Spells' menu item
        if ImGui.BeginMenu('Spells##rcmenu'..sectionName..key) then
            for category,subcategories in pairs(spells) do
                -- Spell Subcategories submenu
                if ImGui.BeginMenu(category..'##rcmenu'..sectionName..key..category) then
                    for subcategory,catspells in pairs(subcategories) do
                        -- Subcategory Spell menu
                        if ImGui.BeginMenu(subcategory..'##'..sectionName..key..subcategory) then
                            for i,spell in ipairs(catspells) do
                                if ImGui.MenuItem(spell..'##'..sectionName..key..subcategory) then
                                    config[sectionName][key..index] = spell
                                end
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
                    config[sectionName][key..index] = altAbility
                end
            end
            ImGui.EndMenu()
        end
        -- TODO: also add discs
        ImGui.EndPopup()
    end
end

-- Draw the value and condition of the selected list item
local DrawSelectedItem = function(sectionName, key, value)
    ImGui.Separator()
    ImGui.Text(string.format('%s.%s%d', sectionName, key, selected))
    ImGui.Text('Value: ')
    ImGui.SameLine()
    if config[sectionName][key..selected] == nil then
        config[sectionName][key..selected] = 'NULL'
    end
    ImGui.SetCursorPosX(175)
    config[sectionName][key..selected] = ImGui.InputText('##'..sectionName..key..selected, config[sectionName][key..selected])
    if value['Conditions'] and config[sectionName][sectionName..'COn'] then
        ImGui.Text('Condition: ')
        ImGui.SameLine()
        if config[sectionName][key..'Cond'..selected] == nil then
            config[sectionName][key..'Cond'..selected] = 'NULL'
        end
        ImGui.SetCursorPosX(175)
        config[sectionName][key..'Cond'..selected] = ImGui.InputText('##condition'..sectionName..key..selected, config[sectionName][key..'Cond'..selected])
    end
    ImGui.Separator()
end

local DrawSpellIconOrButton = function(sectionName, key, index, setSelected)
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
                if setSelected then selected = index end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
            ImGui.Text(iniValueParts[1])
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
            if setSelected then selected = index end
        end
        -- Spell picker context menu on right click button
        DrawSpellPicker(sectionName, key, index)
    else
        if ImGui.Button(index..'##'..sectionName..key, 30, 30) then
            if setSelected then selected = index end
        end
        DrawSpellPicker(sectionName, key, index)
    end
end

-- Draw 0..N buttons based on value of XYZSize input
local DrawList = function(sectionName, key, value)
    ImGui.Text(key..'Size: ')
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    if config[sectionName][key..'Size'] == nil then
        config[sectionName][key..'Size'] = 1
    end
    ImGui.SetCursorPosX(175)
    config[sectionName][key..'Size'] = ImGui.InputInt('##sizeinput'..sectionName..key, config[sectionName][key..'Size'])
    if config[sectionName][key..'Size'] < 0 then
        config[sectionName][key..'Size'] = 0
    elseif config[sectionName][key..'Size'] > value['Max'] then
        config[sectionName][key..'Size'] = value['Max']
    end
    if config[sectionName][key..'Size'] < selected then
        selected = 0
    end
    ImGui.PopItemWidth()
    for i=1,config[sectionName][key..'Size'] do
        DrawSpellIconOrButton(sectionName, key, i, true)
        if i%20 ~= 0 and i < config[sectionName][key..'Size'] then
            ImGui.SameLine()
        end
    end
    if selected > 0 then
        DrawSelectedItem(sectionName, key, value)
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
        DrawSpellIconOrButton(sectionName, key, '', false)
        ImGui.SameLine()
        ImGui.PushItemWidth(200)
        config[sectionName][key] = ImGui.InputText('##textinput'..sectionName..key, config[sectionName][key])
        ImGui.PopItemWidth()
    else
        ImGui.PushItemWidth(200)
        if type(config[sectionName][key]) == 'string' then
            config[sectionName][key] = ImGui.InputText('##'..sectionName..key, config[sectionName][key])
        elseif type(config[sectionName][key]) == 'number' then
            config[sectionName][key] = ImGui.InputInt('##'..sectionName..key, config[sectionName][key])
        end
        ImGui.PopItemWidth()
    end
end

-- Draw main On/Off switches for an INI section
local DrawSectionControlSwitches = function(sectionName, sectionProperties)
    if sectionProperties['On'] then
        config[sectionName][sectionName..'On'] = ImGui.Checkbox(sectionName..'On', InitCheckBoxValue(config[sectionName][sectionName..'On']))
    end
    if sectionProperties['COn'] then
        ImGui.SameLine()
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
    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
        INIFileContents = ReadRawINIFile()
    end
    if ImGui.Button('Refresh Raw INI##rawini') then
        INIFileContents = ReadRawINIFile()
    end
    ImGui.SameLine()
    if ImGui.Button('Save Raw INI##rawini') then
        WriteRawINIFile(INIFileContents)
        config = LIP.load(mq.configDir..'\\'..INIFile)
    end
    local x,y = ImGui.GetContentRegionAvail()
    INIFileContents,_ = ImGui.InputTextMultiline("##rawinput", INIFileContents, x-15, y-15, ImGuiInputTextFlags.None)
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
                        selected = 0
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
repeat
    local spell = mq.TLO.Me.Book(spellIter)
    if not spells[spell.Category()] then
        spells[spell.Category()] = {}
    end
    if not spells[spell.Category()][spell.Subcategory()] then
        spells[spell.Category()][spell.Subcategory()] = {}
    end
    if spell.Level() >= myLevel-30 then
        table.insert(spells[spell.Category()][spell.Subcategory()], spell.Name())
    end
    spellIter = spellIter + 1
until mq.TLO.Me.Book(spellIter)() == nil
for i,j in pairs(spells) do
    for k,l in pairs(j) do
        table.sort(spells[i][k], SpellSorter)
    end
end
-- TODO: what's the right way to loop through activated abilities?
for aaIter=1,10000 do
    if mq.TLO.Me.AltAbility(aaIter)() and mq.TLO.Me.AltAbility(aaIter).Spell() then
        table.insert(altAbilities, mq.TLO.Me.AltAbility(aaIter).Name())
    end
    aaIter = aaIter + 1
end
-- TODO: do the same thing for disciplines

mq.imgui.init('MuleAssist', MAUI)

while not terminate do
    mq.delay(100)
end