term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)


aes = require("aes")
sha256 = require("sha256").sha256
config = require("config")
base64 = require("base64")
gui = require("gui")
theme = require("theme")
spk = require("spk")

dofile("/.sPhone/vfs.lua")


function fs.native()
	return fs
end

function os.version()
	return "sPhone "..sPhone.version
end

-- SHELL API


local multishell = multishell
local parentShell = shell
local parentTerm = term.current()

if multishell then
    multishell.setTitle( multishell.getCurrent(), "shell" )
end

local bExit = false
local sDir = (parentShell and parentShell.dir()) or ""
local sPath = (parentShell and parentShell.path()) or ".:/rom/programs"
local tAliases = (parentShell and parentShell.aliases()) or {}
local tCompletionInfo = (parentShell and parentShell.getCompletionInfo()) or {}
local tProgramStack = {}

local shell = {}
local tEnv = {
	[ "shell" ] = shell,
	[ "multishell" ] = multishell,
}

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

local function run( _sCommand, ... )
	local sPath = shell.resolveProgram( _sCommand )
	if sPath ~= nil then
		tProgramStack[#tProgramStack + 1] = sPath
		if multishell then
		    multishell.setTitle( multishell.getCurrent(), fs.getName( sPath ) )
		end
   		local result = os.run( tEnv, sPath, ... )
		tProgramStack[#tProgramStack] = nil
		if multishell then
		    if #tProgramStack > 0 then
    		    multishell.setTitle( multishell.getCurrent(), fs.getName( tProgramStack[#tProgramStack] ) )
    		else
    		    multishell.setTitle( multishell.getCurrent(), "shell" )
    		end
		end
		return result
   	else
    	printError( "No such program" )
    	return false
    end
end

local function tokenise( ... )
    local sLine = table.concat( { ... }, " " )
	local tWords = {}
    local bQuoted = false
    for match in string.gmatch( sLine .. "\"", "(.-)\"" ) do
        if bQuoted then
            table.insert( tWords, match )
        else
            for m in string.gmatch( match, "[^ \t]+" ) do
                table.insert( tWords, m )
            end
        end
        bQuoted = not bQuoted
    end
    return tWords
end

-- Install shell API
function shell.run( ... )
	local tWords = tokenise( ... )
	local sCommand = tWords[1]
	if sCommand then
		return run( sCommand, table.unpack( tWords, 2 ) )
	end
	return false
end

function shell.dir()
	return sDir
end

function shell.setDir( _sDir )
	sDir = _sDir
end

function shell.path()
	return sPath
end

function shell.setPath( _sPath )
	sPath = _sPath
end

function shell.resolve( _sPath )
	local sStartChar = string.sub( _sPath, 1, 1 )
	if sStartChar == "/" or sStartChar == "\\" then
		return fs.combine( "", _sPath )
	else
		return fs.combine( sDir, _sPath )
	end
end

function shell.resolveProgram( _sCommand )
	-- Substitute aliases firsts
	if tAliases[ _sCommand ] ~= nil then
		_sCommand = tAliases[ _sCommand ]
	end

    -- If the path is a global path, use it directly
    local sStartChar = string.sub( _sCommand, 1, 1 )
    if sStartChar == "/" or sStartChar == "\\" then
    	local sPath = fs.combine( "", _sCommand )
    	if fs.exists( sPath ) and not fs.isDir( sPath ) then
			return sPath
    	end
		return nil
    end
    
 	-- Otherwise, look on the path variable
    for sPath in string.gmatch(sPath, "[^:]+") do
    	sPath = fs.combine( shell.resolve( sPath ), _sCommand )
    	if fs.exists( sPath ) and not fs.isDir( sPath ) then
			return sPath
    	end
    end
	
	-- Not found
	return nil
end

function shell.programs( _bIncludeHidden )
	local tItems = {}
	
	-- Add programs from the path
    for sPath in string.gmatch(sPath, "[^:]+") do
    	sPath = shell.resolve( sPath )
		if fs.isDir( sPath ) then
			local tList = fs.list( sPath )
            for n=1,#tList do
                local sFile = tList[n]
				if not fs.isDir( fs.combine( sPath, sFile ) ) and
				   (_bIncludeHidden or string.sub( sFile, 1, 1 ) ~= ".") then
					tItems[ sFile ] = true
				end
			end
		end
    end	

	-- Sort and return
	local tItemList = {}
	for sItem, b in pairs( tItems ) do
		table.insert( tItemList, sItem )
	end
	table.sort( tItemList )
	return tItemList
end

local function completeProgram( sLine )
	if #sLine > 0 and string.sub( sLine, 1, 1 ) == "/" then
	    -- Add programs from the root
	    return fs.complete( sLine, "", true, false )

    else
        local tResults = {}
        local tSeen = {}

        -- Add aliases
        for sAlias, sCommand in pairs( tAliases ) do
            if #sAlias > #sLine and string.sub( sAlias, 1, #sLine ) == sLine then
                local sResult = string.sub( sAlias, #sLine + 1 )
                if not tSeen[ sResult ] then
                    table.insert( tResults, sResult )
                    tSeen[ sResult ] = true
                end
            end
        end

        -- Add programs from the path
        local tPrograms = shell.programs()
        for n=1,#tPrograms do
            local sProgram = tPrograms[n]
            if #sProgram > #sLine and string.sub( sProgram, 1, #sLine ) == sLine then
                local sResult = string.sub( sProgram, #sLine + 1 )
                if not tSeen[ sResult ] then
                    table.insert( tResults, sResult )
                    tSeen[ sResult ] = true
                end
            end
        end

        -- Sort and return
        table.sort( tResults )
        return tResults
    end
end

local function completeProgramArgument( sProgram, nArgument, sPart, tPreviousParts )
    local tInfo = tCompletionInfo[ sProgram ]
    if tInfo then
        return tInfo.fnComplete( shell, nArgument, sPart, tPreviousParts )
    end
    return nil
end

function shell.complete( sLine )
    if #sLine > 0 then
        local tWords = tokenise( sLine )
        local nIndex = #tWords
        if string.sub( sLine, #sLine, #sLine ) == " " then
            nIndex = nIndex + 1
        end
        if nIndex == 1 then
            local sBit = tWords[1] or ""
            local sPath = shell.resolveProgram( sBit )
            if tCompletionInfo[ sPath ] then
                return { " " }
            else
                local tResults = completeProgram( sBit )
                for n=1,#tResults do
                    local sResult = tResults[n]
                    local sPath = shell.resolveProgram( sBit .. sResult )
                    if tCompletionInfo[ sPath ] then
                        tResults[n] = sResult .. " "
                    end
                end
                return tResults
            end

        elseif nIndex > 1 then
            local sPath = shell.resolveProgram( tWords[1] )
            local sPart = tWords[nIndex] or ""
            local tPreviousParts = tWords
            tPreviousParts[nIndex] = nil
            return completeProgramArgument( sPath , nIndex - 1, sPart, tPreviousParts )

        end
    end
	return nil
end

function shell.completeProgram( sProgram )
    return completeProgram( sProgram )
end

function shell.setCompletionFunction( sProgram, fnComplete )
    tCompletionInfo[ sProgram ] = {
        fnComplete = fnComplete
    }
end

function shell.getCompletionInfo()
    return tCompletionInfo
end

function shell.getRunningProgram()
	if #tProgramStack > 0 then
		return tProgramStack[#tProgramStack]
	end
	return nil
end

function shell.setAlias( _sCommand, _sProgram )
	tAliases[ _sCommand ] = _sProgram
end

function shell.clearAlias( _sCommand )
	tAliases[ _sCommand ] = nil
end

function shell.aliases()
	-- Copy aliases
	local tCopy = {}
	for sAlias, sCommand in pairs( tAliases ) do
		tCopy[sAlias] = sCommand
	end
	return tCopy
end

if multishell then
    function shell.openTab( ... )
        local tWords = tokenise( ... )
        local sCommand = tWords[1]
        if sCommand then
        	local sPath = shell.resolveProgram( sCommand )
        	if sPath == "rom/programs/shell" then
                return multishell.launch( tEnv, sPath, table.unpack( tWords, 2 ) )
            elseif sPath ~= nil then
                return multishell.launch( tEnv, "rom/programs/shell", sCommand, table.unpack( tWords, 2 ) )
            else
                printError( "No such program" )
            end
        end
    end

    function shell.switchTab( nID )
        multishell.setFocus( nID )
    end
end

-- Setup paths
local sPath = ".:/rom/programs"
if term.isColor() then
	sPath = sPath..":/rom/programs/advanced"
end
if turtle then
	sPath = sPath..":/rom/programs/turtle"
else
    sPath = sPath..":/rom/programs/rednet:/rom/programs/fun"
    if term.isColor() then
    	sPath = sPath..":/rom/programs/fun/advanced"
    end
end
if pocket then
    sPath = sPath..":/rom/programs/pocket"
end
if commands then
    sPath = sPath..":/rom/programs/command"
end
if http then
	sPath = sPath..":/rom/programs/http"
end
sPath = sPath..":/bin"
shell.setPath( sPath )
help.setPath( "/rom/help" )

-- Setup aliases
shell.setAlias( "ls", "list" )
shell.setAlias( "dir", "list" )
shell.setAlias( "cp", "copy" )
shell.setAlias( "mv", "move" )
shell.setAlias( "rm", "delete" )
shell.setAlias( "clr", "clear" )
shell.setAlias( "rs", "redstone" )
shell.setAlias( "sh", "shell" )
if term.isColor() then
    shell.setAlias( "background", "bg" )
    shell.setAlias( "foreground", "fg" )
end

-- Setup completion functions
local function completeMultipleChoice( sText, tOptions, bAddSpaces )
    local tResults = {}
    for n=1,#tOptions do
        local sOption = tOptions[n]
        if #sOption + (bAddSpaces and 1 or 0) > #sText and string.sub( sOption, 1, #sText ) == sText then
            local sResult = string.sub( sOption, #sText + 1 )
            if bAddSpaces then
                table.insert( tResults, sResult .. " " )
            else
                table.insert( tResults, sResult )
            end
        end
    end
    return tResults
end
local function completePeripheralName( sText, bAddSpaces )
    return completeMultipleChoice( sText, peripheral.getNames(), bAddSpaces )
end
local tRedstoneSides = redstone.getSides()
local function completeSide( sText, bAddSpaces )
    return completeMultipleChoice( sText, tRedstoneSides, bAddSpaces )
end
local function completeFile( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return fs.complete( sText, shell.dir(), true, false )
    end
end
local function completeDir( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return fs.complete( sText, shell.dir(), false, true )
    end
end
local function completeEither( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return fs.complete( sText, shell.dir(), true, true )
    end
end
local function completeEitherEither( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        local tResults = fs.complete( sText, shell.dir(), true, true )
        for n=1,#tResults do
            local sResult = tResults[n]
            if string.sub( sResult, #sResult, #sResult ) ~= "/" then
                tResults[n] = sResult .. " "
            end
        end
        return tResults
    elseif nIndex == 2 then
        return fs.complete( sText, shell.dir(), true, true )
    end
end
local function completeProgram( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return shell.completeProgram( sText )
    end
end
local function completeHelp( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return help.completeTopic( sText )
    end
end
local function completeAlias( shell, nIndex, sText, tPreviousText )
    if nIndex == 2 then
        return shell.completeProgram( sText )
    end
end
local function completePeripheral( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completePeripheralName( sText )
    end
end
local tGPSOptions = { "host", "host ", "locate" }
local function completeGPS( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tGPSOptions )
    end
end
local tLabelOptions = { "get", "get ", "set ", "clear", "clear " }
local function completeLabel( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tLabelOptions )
    elseif nIndex == 2 then
        return completePeripheralName( sText )
    end
end
local function completeMonitor( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completePeripheralName( sText, true )
    elseif nIndex == 2 then
        return shell.completeProgram( sText )
    end
end
local tRedstoneOptions = { "probe", "set ", "pulse " }
local function completeRedstone( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tRedstoneOptions )
    elseif nIndex == 2 then
        return completeSide( sText )
    end
end
local tDJOptions = { "play", "play ", "stop " }
local function completeDJ( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tDJOptions )
    elseif nIndex == 2 then
        return completePeripheralName( sText )
    end
end
local tPastebinOptions = { "put ", "get ", "run " }
local function completePastebin( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tPastebinOptions )
    elseif nIndex == 2 then
        if tPreviousText[2] == "put" then
            return fs.complete( sText, shell.dir(), true, false )
        end
    end
end
local tChatOptions = { "host ", "join " }
local function completeChat( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tChatOptions )
    end
end
local function completeSet( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, settings.getNames(), true )
    end
end
shell.setCompletionFunction( "rom/programs/alias", completeAlias )
shell.setCompletionFunction( "rom/programs/cd", completeDir )
shell.setCompletionFunction( "rom/programs/copy", completeEitherEither )
shell.setCompletionFunction( "rom/programs/delete", completeEither )
shell.setCompletionFunction( "rom/programs/drive", completeDir )
shell.setCompletionFunction( "rom/programs/edit", completeFile )
shell.setCompletionFunction( "rom/programs/eject", completePeripheral )
shell.setCompletionFunction( "rom/programs/gps", completeGPS )
shell.setCompletionFunction( "rom/programs/help", completeHelp )
shell.setCompletionFunction( "rom/programs/id", completePeripheral )
shell.setCompletionFunction( "rom/programs/label", completeLabel )
shell.setCompletionFunction( "rom/programs/list", completeDir )
shell.setCompletionFunction( "rom/programs/mkdir", completeFile )
shell.setCompletionFunction( "rom/programs/monitor", completeMonitor )
shell.setCompletionFunction( "rom/programs/move", completeEitherEither )
shell.setCompletionFunction( "rom/programs/redstone", completeRedstone )
shell.setCompletionFunction( "rom/programs/rename", completeEitherEither )
shell.setCompletionFunction( "rom/programs/shell", completeProgram )
shell.setCompletionFunction( "rom/programs/type", completeEither )
shell.setCompletionFunction( "rom/programs/set", completeSet )
shell.setCompletionFunction( "rom/programs/advanced/bg", completeProgram )
shell.setCompletionFunction( "rom/programs/advanced/fg", completeProgram )
shell.setCompletionFunction( "rom/programs/fun/dj", completeDJ )
shell.setCompletionFunction( "rom/programs/fun/advanced/paint", completeFile )
shell.setCompletionFunction( "rom/programs/http/pastebin", completePastebin )
shell.setCompletionFunction( "rom/programs/rednet/chat", completeChat )

-- END SHELL API

-- CUSTOM FUNCTIONS

local oldShutdown = os.shutdown
local oldReboot = os.reboot

function os.shutdown()
		local w, h = term.getSize()
		local text = "Shutting down"
		local x = math.ceil(w/2)-math.ceil(#text/2)+1
		local y = math.ceil(h/2)
		sPhone.inHome = false
		os.pullEvent = os.pullEventRaw
		local function printMsg(color)
			term.setBackgroundColor(color)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(x,y)
			print(text)
			sleep(0.1)
		end
		printMsg(colors.white)
		printMsg(colors.lightGray)
		printMsg(colors.gray)
		printMsg(colors.black)
		sleep(0.6)
		oldShutdown()
	end
	
	function os.reboot()
		local w, h = term.getSize()
		local text = "Rebooting"
		local x = math.ceil(w/2)-math.ceil(#text/2)+1
		local y = math.ceil(h/2)
		sPhone.inHome = false
		os.pullEvent = os.pullEventRaw
		local function printMsg(color)
			term.setBackgroundColor(color)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(x,y)
			print(text)
			sleep(0.1)
		end
		printMsg(colors.white)
		printMsg(colors.lightGray)
		printMsg(colors.gray)
		printMsg(colors.black)
		sleep(0.6)
		oldReboot()
	end

function string.getExtension(name)
	local ext = ""
	local exten = false
	name = string.reverse(name)
	for i = 1, #name do
		local s = string.sub(name,i,i)
		if s == "." then
			ch = i - 1
			exten = true
			break
		end
	end
	if exten then
		ext = string.sub(name, 1, ch)
		return string.reverse(ext)
	else
		return nil
	end
end

function _G.read( _sReplaceChar, _tHistory, _fnComplete, _MouseEvent, _presetInput, _rawEvent )
    term.setCursorBlink( true )
    local sLine = _presetInput
		
		if type(sLine) ~= "string" then
			sLine = ""
		end
		local nPos = #sLine
    local nHistoryPos
		local _MouseX
		local _MouseY
		local param
		local sEvent
		local usedMouse = false
    if _sReplaceChar then
        _sReplaceChar = string.sub( _sReplaceChar, 1, 1 )
    end

    local tCompletions
    local nCompletion
    local function recomplete()
        if _fnComplete and nPos == string.len(sLine) then
            tCompletions = _fnComplete( sLine )
            if tCompletions and #tCompletions > 0 then
                nCompletion = 1
            else
                nCompletion = nil
            end
        else
            tCompletions = nil
            nCompletion = nil
        end
    end

    local function uncomplete()
        tCompletions = nil
        nCompletion = nil
    end

    local w = term.getSize()
    local sx = term.getCursorPos()

    local function redraw( _bClear )
        local nScroll = 0
        if sx + nPos >= w then
            nScroll = (sx + nPos) - w
        end

        local cx,cy = term.getCursorPos()
        term.setCursorPos( sx, cy )
        local sReplace = (_bClear and " ") or _sReplaceChar
        if sReplace then
            term.write( string.rep( sReplace, math.max( string.len(sLine) - nScroll, 0 ) ) )
        else
            term.write( string.sub( sLine, nScroll + 1 ) )
        end

        if nCompletion then
            local sCompletion = tCompletions[ nCompletion ]
            local oldText, oldBg
            if not _bClear then
                oldText = term.getTextColor()
                oldBg = term.getBackgroundColor()
                term.setTextColor( colors.gray )
            end
            if sReplace then
                term.write( string.rep( sReplace, string.len( sCompletion ) ) )
            else
                term.write( sCompletion )
            end
            if not _bClear then
                term.setTextColor( oldText )
                term.setBackgroundColor( oldBg )
            end
        end

        term.setCursorPos( sx + nPos - nScroll, cy )
    end
    
    local function clear()
        redraw( true )
    end

    recomplete()
    redraw()

    local function acceptCompletion()
        if nCompletion then
            -- Clear
            clear()

            -- Find the common prefix of all the other suggestions which start with the same letter as the current one
            local sCompletion = tCompletions[ nCompletion ]
            sLine = sLine .. sCompletion
            nPos = string.len( sLine )

            -- Redraw
            recomplete()
            redraw()
        end
    end
    while true do
        sEvent, param,_MouseX,_MouseY = os.pullEvent()
        if sEvent == "char" then
            -- Typed key
            clear()
            sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
            nPos = nPos + 1
            recomplete()
            redraw()

        elseif sEvent == "paste" then
            -- Pasted text
            clear()
            sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
            nPos = nPos + string.len( param )
            recomplete()
            redraw()

        elseif sEvent == "key" then
            if param == keys.enter then
                -- Enter
                if nCompletion then
                    clear()
                    uncomplete()
                    redraw()
                end
                break
                
            elseif param == keys.left then
                -- Left
                if nPos > 0 then
                    clear()
                    nPos = nPos - 1
                    recomplete()
                    redraw()
                end
                
            elseif param == keys.right then
                -- Right                
                if nPos < string.len(sLine) then
                    -- Move right
                    clear()
                    nPos = nPos + 1
                    recomplete()
                    redraw()
                else
                    -- Accept autocomplete
                    acceptCompletion()
                end

            elseif param == keys.up or param == keys.down then
                -- Up or down
                if nCompletion then
                    -- Cycle completions
                    clear()
                    if param == keys.up then
                        nCompletion = nCompletion - 1
                        if nCompletion < 1 then
                            nCompletion = #tCompletions
                        end
                    elseif param == keys.down then
                        nCompletion = nCompletion + 1
                        if nCompletion > #tCompletions then
                            nCompletion = 1
                        end
                    end
                    redraw()

                elseif _tHistory then
                    -- Cycle history
                    clear()
                    if param == keys.up then
                        -- Up
                        if nHistoryPos == nil then
                            if #_tHistory > 0 then
                                nHistoryPos = #_tHistory
                            end
                        elseif nHistoryPos > 1 then
                            nHistoryPos = nHistoryPos - 1
                        end
                    else
                        -- Down
                        if nHistoryPos == #_tHistory then
                            nHistoryPos = nil
                        elseif nHistoryPos ~= nil then
                            nHistoryPos = nHistoryPos + 1
                        end                        
                    end
                    if nHistoryPos then
                        sLine = _tHistory[nHistoryPos]
                        nPos = string.len( sLine ) 
                    else
                        sLine = ""
                        nPos = 0
                    end
                    uncomplete()
                    redraw()

                end

            elseif param == keys.backspace then
                -- Backspace
                if nPos > 0 then
                    clear()
                    sLine = string.sub( sLine, 1, nPos - 1 ) .. string.sub( sLine, nPos + 1 )
                    nPos = nPos - 1
                    recomplete()
                    redraw()
                end

            elseif param == keys.home then
                -- Home
                if nPos > 0 then
                    clear()
                    nPos = 0
                    recomplete()
                    redraw()
                end

            elseif param == keys.delete then
                -- Delete
                if nPos < string.len(sLine) then
                    clear()
                    sLine = string.sub( sLine, 1, nPos ) .. string.sub( sLine, nPos + 2 )                
                    recomplete()
                    redraw()
                end

            elseif param == keys["end"] then
                -- End
                if nPos < string.len(sLine ) then
                    clear()
                    nPos = string.len(sLine)
                    recomplete()
                    redraw()
                end

            elseif param == keys.tab then
                -- Tab (accept autocomplete)
                acceptCompletion()

            end

        elseif sEvent == "term_resize" then
            -- Terminal resized
            w = term.getSize()
            redraw()
				
				elseif sEvent == "mouse_click" and _MouseEvent then
					if nCompletion then
            clear()
            uncomplete()
            redraw()
          end
					usedMouse = true
					break
        end
    end

    local cx, cy = term.getCursorPos()
    term.setCursorBlink( false )
    term.setCursorPos( w + 1, cy )
    print()
		if sEvent == "mouse_click" then
			return sLine, param, _MouseX, _MouseY
		end
    return sLine
	end
	
function sPhone.getUsername()
	return config.get("account","username") or "Guest"
end

function sPhone.setDefaultApp(app,appid)
	
end

function sPhone.getDefaultApp(app)
	
end

local function home()
	
end
	
function sPhone.lock()
	local old = os.pullEvent
	os.pullEvent = os.pullEventRaw
	local pw = ""
	local w,h = term.getSize()
	gui.clear()
	gui.header("Welcome back, "..sPhone.getUsername(),nil,true)
	term.setCursorPos(w-8,h-1)
	write("Unlock >")
	term.setCursorPos(2,6)
	print("Password")
	paintutils.drawLine(2,7,24,7,colors.lightGray)
	os.queueEvent("mouse_click",1,2,7)
	while true do
		local _,_,x,y = os.pullEvent("mouse_click")
		if y == 7 and (x>=2 and x<=24) then
			term.setCursorPos(2,7)
			term.redirect(window.create(term.native(),2,7,23,1,true))
			term.setBackgroundColor(colors.lightGray)
			term.setTextColor(colors.white)
			term.clear()
			pw, mouse, mx,my = read("*",nil,nil,true,pw)
			term.redirect(term.native())
			paintutils.drawLine(2,7,24,7,colors.lightGray)
			term.setCursorPos(2,7)
			for i = 1,#pw do
				write("*")
			end
			if mouse then
				os.queueEvent("mouse_click",mouse,mx,my)
			else
				os.queueEvent("mouse_click",1,w-7,h-1)
			end
		elseif y == h-1 and (x>=w-8 and x<=w-1) then
			if pw and sha256(pw) == config.get("account","password") then
				os.pullEvent = old
				gui.clear(true)
				break
			else
				term.setCursorPos(2,8)
				term.setTextColor(colors.red)
				term.setBackgroundColor(colors.white)
				print("Wrong Password")
			end
		end
	end
	return
end

-- SETUP

local setopts = {
	user = "",
	pass = nil,
	rpass = nil,
}
local w,h = term.getSize()
local mouse, mx,my
local nat = term.native()
if config.get("os","setup") ~= false then
	gui.clear()
	gui.header("Welcome to sPhone",nil,true)
	term.setCursorPos(2,5)
	print("Username")
	paintutils.drawLine(2,6,24,6,colors.lightGray)
	term.setBackgroundColor(colors.white)
	term.setTextColor(colors.black)
	term.setCursorPos(2,8)
	print("Password")
	paintutils.drawLine(2,9,24,9,colors.lightGray)
	term.setBackgroundColor(colors.white)
	term.setTextColor(colors.black)
	term.setCursorPos(2,11)
	print("Re-type password")
	paintutils.drawLine(2,12,24,12,colors.lightGray)
	term.setCursorPos(w-6,h-1)
	term.setBackgroundColor(colors.white)
	term.setTextColor(colors.black)
	write("Next >")
	
	while true do
		local _,_,x,y = os.pullEvent("mouse_click")
		if y == 6 and (x>=2 and x<=24) then
			term.setCursorPos(2,6)
			term.redirect(window.create(nat,2,6,23,1,true))
			term.setBackgroundColor(colors.lightGray)
			term.setTextColor(colors.white)
			term.clear()
			setopts.user, mouse, mx,my = read(nil,nil,nil,true,setopts.user)
			term.redirect(nat)
			paintutils.drawLine(2,6,24,6,colors.lightGray)
			term.setCursorPos(2,6)
			write(setopts.user)
			if mouse then
				os.queueEvent("mouse_click",mouse,mx,my)
			else
				os.queueEvent("mouse_click",1,2,9)
			end
		elseif y == 9 and (x>=2 and x<=24) then
			term.setCursorPos(2,9)
			term.redirect(window.create(nat,2,9,23,1,true))
			term.setBackgroundColor(colors.lightGray)
			term.setTextColor(colors.white)
			term.clear()
			setopts.pass, mouse, mx,my = read("*",nil,nil,true,setopts.pass)
			term.redirect(nat)
			paintutils.drawLine(2,9,24,9,colors.lightGray)
			term.setCursorPos(2,9)
			for _ = 1,#setopts.pass do
				write("*")
			end
			if mouse then
				os.queueEvent("mouse_click",mouse,mx,my)
			else
				os.queueEvent("mouse_click",1,2,12)
			end
		elseif y == 12 and (x>=2 and x<=24) then
			term.setCursorPos(2,12)
			term.redirect(window.create(nat,2,12,23,1,true))
			term.setBackgroundColor(colors.lightGray)
			term.setTextColor(colors.white)
			term.clear()
			setopts.rpass, mouse, mx,my = read("*",nil,nil,true,setopts.rpass)
			term.redirect(nat)
			paintutils.drawLine(2,12,24,12,colors.lightGray)
			term.setCursorPos(2,12)
			for _ = 1,#setopts.rpass do
				write("*")
			end
			term.setCursorPos(25,12)
			term.setBackgroundColor(colors.white)
			write(" ")
			if mouse then
				os.queueEvent("mouse_click",mouse,mx,my)
			else
				os.queueEvent("mouse_click",1,w-6,h-1)
			end
		elseif y == h-1 and (x>= w-6 and x<=w-1) then
			if setopts.pass or setopts.rpass then
				if setopts.rpass ~= setopts.pass then
					term.setCursorPos(25,12)
					term.setBackgroundColor(colors.white)
					term.setTextColor(colors.red)
					write("*")
				else
					term.setCursorPos(25,12)
					term.setBackgroundColor(colors.white)
					write(" ")
					
					config.set("account","password",sha256(setopts.pass))
				end
			end
			config.set("account","username",setopts.user)
			config.set("os","setup",false)
			break
		end
	end
end

-- END SETUP

sPhone.lock()
shell.run("shell")
while true do
	if not sPhone.home then
		spk.launch("sphone.shell")
	end
	sleep(0)
end