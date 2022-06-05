-- Stop, don't look at this! Just some WIP stuff, nothing to see here.
local schema = {
    StartCommand = '/rgstart',
    INI_PATTERNS = {
        ['nolevel'] = 'rgmercs/PCinis/RGBRD_%s_%s.ini',
    },
    -- Array For tab and INI ordering purposes
    Sections = {
        'General',
        'Debug',
        'Hotkeys',
        'Options',
        'Combat',
        'Healing',
        'Item',
        'Mount',
        'ZoneLogic',
        'Pull',
        'Mez',
    },
    General = {
        Properties = {
            ReturnToCamp={-- int (30)
                Type='SWITCH',
                Min=0,
                Tooltip='',
            },
        }
    },
    Debug = {
        Properties = {

        }
    },
    Hotkeys = {
        Properties = {
            
        }
    }
}

return schema
