--- @type mq
local mq = require 'mq'
local globals = require 'ma.globals'
local utils = require 'ma.utils'
local LIP = require 'ma.LIP'

local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.Hideable, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.BordersOuter)
local LEMONS_INFO_INI = mq.configDir..'/Lemons_Info.ini'
local MA_LISTS = {'FireMobs','ColdMobs','MagicMobs','PoisonMobs','DiseaseMobs','SlowMobs'}

local lemons_info = {}
local DEBUG = {all=false,dps=false,heal=false,buff=false,cast=false,combat=false,move=false,mez=false,pet=false,pull=false,chain=false,target=false}
local debugCaptureTime = '60'

local selectedDebug = 'all' -- debug dropdown menu selection
local selectedSharedList = nil -- shared lists table selected list
local selectedSharedListItem = nil -- shared lists list table selected entry

if utils.FileExists(LEMONS_INFO_INI) then
    lemons_info = LIP.load(LEMONS_INFO_INI, true)
end

local function DrawRawINIEditTab()
    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
        if utils.FileExists(mq.configDir..'/'..globals.INIFile) then
            globals.INIFileContents = utils.ReadRawINIFile()
        end
    end
    if ImGui.Button('Refresh Raw INI##rawini') then
        if utils.FileExists(mq.configDir..'/'..globals.INIFile) then
            globals.INIFileContents = utils.ReadRawINIFile()
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Save Raw INI##rawini') then
        utils.WriteRawINIFile(globals.INIFileContents)
        globals.Config = LIP.load(mq.configDir..'/'..globals.INIFile)
    end
    local x,y = ImGui.GetContentRegionAvail()
    globals.INIFileContents,_ = ImGui.InputTextMultiline("##rawinput", globals.INIFileContents or '', x-15, y-15, ImGuiInputTextFlags.None)
end

local function DrawListsTab()
    ImGui.PushTextWrapPos(ImGui.GetContentRegionAvail()-10)
    ImGui.TextColored(0, 1, 1, 1, "View shared list content from Lemons_Info.ini. To add entries, use the macro /addxyz commands and click reload.")
    ImGui.PopTextWrapPos()
    ImGui.Text('Select a list below to edit:')
    ImGui.SameLine()
    if ImGui.SmallButton('Save Lemons INI') then
        LIP.save(LEMONS_INFO_INI, lemons_info, globals.Schema)
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Reload Lemons INI') then
        if utils.FileExists(LEMONS_INFO_INI) then
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

-- Define this down here since the functions need to be defined first
local customSections = {
    ['Raw INI']=DrawRawINIEditTab,
    ['Shared Lists']=DrawListsTab,
    ['Debug']=DrawDebugTab
}

return customSections