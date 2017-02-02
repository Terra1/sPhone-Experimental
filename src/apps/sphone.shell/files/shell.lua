sPhone.home = true
-- Colours
local promptColour, textColour, bgColour
if term.isColour() then
	promptColour = colours.yellow
	textColour = colours.white
	bgColour = colours.black
else
	promptColour = colours.white
	textColour = colours.white
	bgColour = colours.black
end

local parentTerm = term.current()
require("gui").clear(true)

local bExit = false

function shell.exit()
    bExit = true
	sPhone.home = false
end

local tArgs = { ... }
if #tArgs > 0 then
    -- "shell x y z"
    -- Run the program specified on the commandline
    shell.run( ... )

else
    -- "shell"
    -- Print the header
    term.setBackgroundColor( bgColour )
    term.setTextColour( promptColour )
    print( os.version() )
    term.setTextColour( textColour )

    -- Read commands and execute them
    local tCommandHistory = {}
    while not bExit do
        term.redirect( parentTerm )
        term.setBackgroundColor( bgColour )
        term.setTextColour( promptColour )
        write( shell.dir() .. "> " )
        term.setTextColour( textColour )


        local sLine
        if settings.get( "shell.autocomplete" ) then
            sLine = read( nil, tCommandHistory, shell.complete )
        else
            sLine = read( nil, tCommandHistory )
        end
        table.insert( tCommandHistory, sLine )
        shell.run( sLine )
    end
end