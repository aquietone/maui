--[[
	Copyright (c) 2012 Carreras Nicolas
	
	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
--]]
--- Lua INI Parser.
-- It has never been that simple to use INI files with Lua.
--@author Dynodzzo

local LIP = {};

--- Returns a table containing all the data from the INI file.
--@param fileName The name of the INI file to parse. [string]
--@return The table containing all data from the INI file. [table]
function LIP.load(fileName, initNilValues)
	assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.');
	local file = assert(io.open(fileName, 'r'), 'Error loading file : ' .. fileName);
	local data = {};
	local section;
	for line in file:lines() do
		local tempSection = line:match('^%[([^%[%]]+)%]$');
		if(tempSection)then
			section = tonumber(tempSection) and tonumber(tempSection) or tempSection;
			data[section] = data[section] or {};
		end
		--local param, value = line:match('^([%w|_]+)%s-=%s-(.+)$');
		-- include keys with spaces
		--local param, value = line:match("^([%w|_'.%s-]+)=%s-(.+)$");
		-- read keys with no value
		local param, value = line:match("^([%w|_'.%s-]+)=(.-)$");
		if(param and value ~= nil)then
			if(tonumber(value))then
				value = tonumber(value);
			elseif(value == 'true')then
				value = true;
			elseif(value == 'false')then
				value = false;
			end
			if(tonumber(param))then
				param = tonumber(param);
			end
			data[section][param] = value;
		elseif param and initNilValues then
			data[section][param] = 0
		end
	end
	file:close();
	return data;
end

local KeySorter = function(a, b)
	local aNum = tonumber(a:match('%d+'))
	local bNum = tonumber(b:match('%d+'))
	if aNum and bNum and aNum < bNum then
		return true
	elseif aNum and bNum and bNum < aNum then
		return false
	elseif a < b then
		return true
	elseif b > a then
		return false
	else
		return false
	end
end

--- Saves all the data from a table to an INI file.
--@param fileName The name of the INI file to fill. [string]
--@param data The table containing all the data to store. [table]
function LIP.save(fileName, data, schema)
	assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.');
	assert(type(data) == 'table', 'Parameter "data" must be a table.');
	local file = assert(io.open(fileName, 'w+b'), 'Error loading file :' .. fileName);
	local contents = '';

	for _, sectionKey in ipairs(schema.Sections) do
		if data[sectionKey] and next(data[sectionKey]) ~= nil then
			contents = contents .. ('[%s]\n'):format(sectionKey);
			-- sort the keys before writing the file
			local keys = {}
			for k, v in pairs(data[sectionKey]) do table.insert(keys, k) end
			table.sort(keys, KeySorter)

			for _, k in ipairs(keys) do
				local value = data[sectionKey][k]
				if value == true then
					value = 1
				elseif value == false then
					value = 0
				end
				contents = contents .. ('%s=%s\n'):format(k, tostring(value));
			end
			contents = contents .. '\n';
		end
	end
	file:write(contents);
	file:close();
end

return LIP;