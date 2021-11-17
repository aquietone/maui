local schemas = {'ma', 'ka', 'test'}

local globals = {
    Version = '0.6.0',
    INIFile = nil, -- file name of character INI to load
    INIFileContents = nil, -- raw file contents for raw INI tab
    Config = nil, -- lua table version of INI content
    MyServer = nil, -- the server of the character running MAUI
    NyName = nil, -- the name of the character running MAUI
    MyLevel = nil, -- the level of the character running MAUI
    MyClass = nil, -- the class of the character running MAUI,
    Schemas = schemas, -- the available macro schemas which MAUI supports
    CurrentSchema = nil, -- the name of the current macro schema being used
    Schema = nil, -- the loaded schema
}

return globals