# Extending MAUI to support other INI based macros

## Addons folder

Add a new addon file such as `ka.lua`.

## Schemas folder

Add a new schema file such as `ka.lua`.

## globals.lua

Add a new value to the schemas table in `globals.lua`: `local schemas = {'ma', 'ka'}`. The value should match the name of the schema and addon files.

# Adding schemas for KA like macros

MAUI relies heavily on the fact that KA and MA are almost identical to each other.
A macro with a different configuration structure won't work at all.
A macro with INI configuration may have some varying degree of success depending how similar it is to MA.

## Creating the schema file in the schemas folder

Just copy one of the existing ones and fit it to the new macro.

- Define the INI file pattern -- this needs to be refactored some really to handle differing # of inputs to the formatted string for different macros, i.e. KA doesn't include server name while MA does.

```lua
    INI_PATTERNS = {
            ['level'] = 'MuleAssist_%s_%s_%d.ini',
            ['nolevel'] = 'MuleAssist_%s_%s.ini',
    },
```

Right now, things are hardcoded to know what pattern to use and how many variable replacements there should be:

```lua
    if currentSchema == 'ma' then
        if FileExists(mq.configDir..'/'..schema['INI_PATTERNS']['level']:format(myServer, myName, myLevel)) then
            return schema['INI_PATTERNS']['level']:format(myServer, myName, myLevel)
```

- Define the default start command.

```lua
    StartCommand = '/mac muleassist assist ${Group.MainAssist}',
```

- Define the section ordering that will be used to write the INI in a particular order.

```lua
    Sections = {
        'General',
        'DPS',
        'Heals',
        'Buffs',
        'Melee',
        'Burn',
        'Mez',
        'AE',
        'OhShit',
        'Pet',
        'Pull',
        'Aggro',
        'Bandolier',
        'Cures',
        'GoM',
        'Merc',
        'AFKTools',
        'GMail',
        'MySpells',
        'SpellSet',
    },
```

- Define each section and its control switches and properties.

```lua
    Melee={
        Controls={
            On={
                Type='SWITCH',
            },
        },
        Properties={
            AssistAt={
                Type='NUMBER',
                Min=1,
                Max=100,
                Tooltip='Mob health to assist/attack. This affects when you engage and is NOT specific to melee characters. IE pet classes will send pets at this %%.',
            },
        },
    },
```

## Add the schema name to the list of schemas

In `start.lua`:
```lua
local schemas = {'ma','ka'}
```

## Implement custom sections

To have entries on the left hand panel that don't correspond to a section in the INI file, currently they
are implemented as "custom" sections.

In `start.lua`:
```lua
-- Define this down here since the functions need to be defined first
local customSections = {
    ['ma'] = {['Raw INI']=DrawRawINIEditTab, ['Shared Lists']=DrawListsTab, ['Debug']=DrawDebugTab},
    ['ka'] = {['Raw INI']=DrawRawINIEditTab}
}
```

Ideally these would be refactored out into pluggable per-macro impl and included like the schemas, but they aren't for now.
