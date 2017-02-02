local function crash(erro)
	term.setBackgroundColor(colors.red)
	term.setTextColor(colors.white)
	term.clear()
	term.setCursorPos(1,1)
	print("sPhone crashed")
	term.setCursorPos(1,3)
	print(erro or "n/a")
	os.pullEventRaw("crash")
	_G.term = nil
end
local w,h = term.getSize()
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.white)
print("Sertex")
term.setCursorPos(2,h)
write("Press ALT to enter BIOS")
local timer = os.startTimer(1)
while true do
	local event, k = os.pullEvent()
	if event == "timer" and k == timer then
		break
	elseif event == "key" and k == 56 then
		return
	end
end

function _G.require(lib) --raping _G
	if not lib then
		return nil
	end
	if fs.exists("/.sPhone/apis/"..fs.getName(lib)) and not fs.isDir("/.sPhone/apis/"..fs.getName(lib)) then
		lib = "/.sPhone/apis/"..fs.getName(lib)
	elseif fs.exists("/rom/apis/"..fs.getName(lib)) and not fs.isDir("/rom/apis/"..fs.getName(lib)) then
		lib = "/rom/apis/"..fs.getName(lib)
	elseif fs.exists(lib) then
		lib = lib --?
	elseif _G[lib] and type(_G[lib]) == "table" then
		return _G[lib]
	end
	
	
    local tEnv = {}
    setmetatable( tEnv, { __index = _G } )
    local fnAPI, err = loadfile( lib, tEnv )
    if fnAPI then
        local ok, err = pcall( fnAPI )
        if not ok then
            printError( err )
            return nil
        end
    else
        printError( err )
        return nil
    end
    
    local tAPI = {}
    for k,v in pairs( tEnv ) do
        if k ~= "_ENV" then
            tAPI[k] =  v
        end
    end

    return tAPI    
end

_G.proc = {}
local _proc = {}
local _killProc = {}
function proc.signal(pid, sig)
	local p = _proc[pid]
	if p then
		if not p.filter or p.filter == "signal" then
			local ok, rtn = coroutine.resume(p.co, "signal", tostring(sig))
			if ok then
				p.filter = rtn
			end
		end
		return true
	end
	return false
end
function proc.kill(pid)
	_killProc[pid] = true
end
function proc.launch(fn, name)
	_proc[#_proc + 1] = {
		name = name or tostring(#_proc + 1),
		co = coroutine.create(setfenv(fn, getfenv())),
	}
	return true
end
function proc.getInfo()
	local t = {}
	for pid, v in pairs(_proc) do
		t[pid] = v.name
	end
	return t
end

_G.sPhone = {
	version = 2.0,
}

proc.launch(function()
	local ok,err = pcall(function()
		setfenv(loadfile("/.sPhone/sPhone.lua"), setmetatable({
				crash = crash,
				require = require,
				proc = proc,
			}, {__index = getfenv()}))()
	end)
	if not ok then
		crash(err)
	end
end, "sPhone OS")

os.queueEvent("multitask")
while _proc[1] ~= nil do
  local ev = {os.pullEventRaw()}
  for pid, v in pairs(_proc) do
    if not v.filter or ev[1] == "terminate" or v.filter == ev[1] then
			local ok, rtn = coroutine.resume(v.co, unpack(ev))
      if ok then
        v.filter = rtn
      end
    end
    if coroutine.status(v.co) == "dead" then
      _killProc[pid] = true
    end
  end
  for pid in pairs(_killProc) do
		_proc[pid] = nil
  end
  if next(_killProc) then
    _killProc = {}
  end
end
shell = nil