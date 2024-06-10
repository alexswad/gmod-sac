local Commands = {}
local CommandLookup = {}
function SAdminCon:AddCommand(name, cat, func, desc, input, short)
	Commands[name] = {
		cat = cat or "general",
		func = func,
		desc = desc,
		input = input,
		short = short,
		name = name,
	}
	CommandLookup[name] = Commands[name]
	if short then CommandLookup[short] = Commands[name] end
end

function SAdminCon:RemoveCommand(name)
	local tab = Commands[name]
	if not tab then return end
	if tab.short then CommandLookup[tab.short] = nil end
	Commands[name] = nil
	CommandLookup[name] = nil
end

if SERVER then
	function SAdminCon:RunCommand(ply, cmd, argstr)
		if isstring(cmd) then cmd = CommandLookup[cmd] end
		if IsValid(ply) then
			if cmd.cat == "tp" then
				local tp = self.tp_convar:GetInt()
				if tp == 0 and not SAdminCon:IsAdmin(ply) then
					return false, "You must be an Admin to run this command!"
				elseif tp == 1 and cmd.name ~= "goto" then
					return false, "You must be an Admin to run this command!"
				end
			elseif cmd.cat == "admin" and not SAdminCon:IsAdmin(ply) then
				return false, "You must be an Admin to run this command!"
			elseif cmd.cat == "superadmin" and not SAdminCon:CanEdit(ply) then
				return false, "You must be a Superadmin to run this command!"
			end
		end

		local earg = string.Explode(" ", argstr or "")
		local args, skipto = {}
		for k, v in ipairs(earg) do
			if v:Trim() == "" or (skipto and k <= skipto) then continue end
			if v:StartsWith("\"") then
				local n, nstr = k + 1, v:sub(2)
				while earg[n] do
					nstr = nstr .. " " .. earg[n]
					skipto = n
					if nstr:EndsWith("\"") then break end
					n = n + 1
				end

				args[#args + 1] = nstr:TrimRight("\"")
				continue
			end
			if v:StartsWith("\'") then
				local n, nstr = k + 1, v:sub(2)
				while earg[n] do
					nstr = nstr .. " " .. earg[n]
					skipto = n
					if nstr:EndsWith("\'") then break end
					n = n + 1
				end

				args[#args + 1] = nstr:TrimRight("\'")
				continue
			end
			args[#args + 1] = v
		end

		return cmd.func(ply, args, argstr:Trim() or "")
	end

	hook.Add("PlayerSay", "SAC_ONCHAT", function(ply, str)
		if SAdminCon.disable_chat:GetBool() then return end

		local strtab = string.Explode(" ", str)
		local cmd, argstr = strtab[1]:TrimLeft(SAdminCon.GetPrefix()), str:sub(#strtab[1] + 1)
		if strtab[1]:StartsWith(SAdminCon.GetPrefix()) and CommandLookup[cmd] then
			local res, err = SAdminCon:RunCommand(ply, cmd, argstr:Trim())
			if res == false then
				ply:ChatPrint("[SAC] Command failed: " .. err)
			elseif res then
				if SAdminCon.announce_convar:GetBool() then
					MsgAll("[SAC] " .. res)
				else
					ply:ChatPrint("[SAC] " .. res)
					print("[SAC] " .. res)
				end
			end
			return ""
		end
	end)
end

local function findplayer(str)
	local targets = {}
	if not str then return targets end
	str = str:lower()
	for k, v in pairs(player.GetAll()) do
		if string.find(v:Name():lower(), str, 1, true) then
			targets[#targets + 1] = v
		end
	end
	return targets
end

local function checktarget(targets)
	if #targets < 1 then
		return false, "No player found!"
	elseif #targets > 1 then
		local plys = ""
		for k, v in pairs(targets) do
			plys = plys .. v:Name() .. ", "
		end
		return false, "Multiple players found: " .. plys:TrimRight(", ")
	end
	return targets[1]
end

local function ActivateNoCollision(target, min)
	local oldCollision = target:GetCollisionGroup() or COLLISION_GROUP_PLAYER
	target:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) -- Players can walk through target
	if (min and (tonumber(min) > 0)) then
		timer.Simple(min, function() --after 'min' seconds
			timer.Create(target:SteamID64() .. "_checkBounds_cycle", 0.5, 0, function() -- check every half second
				local penetrating = ( target:GetPhysicsObject() and target:GetPhysicsObject():IsPenetrating() ) or false --if we are penetrating an object
				local tooNearPlayer = false --or inside a player's hitbox
				for i, ply in ipairs( player.GetAll() ) do
					if target:GetPos():DistToSqr(ply:GetPos()) <= (80 * 80) then
						tooNearPlayer = true
					end
				end
				if not (penetrating and tooNearPlayer) then --if both false then 
					target:SetCollisionGroup(oldCollision) -- Stop no-colliding by returning the original collision group (or default player collision)
					timer.Remove(target:SteamID64() .. "_checkBounds_cycle")
				end
			end)
		end)
	end
end

local function targetString(str, ...)
	local targets = {}
	for k, v in ipairs({...}) do
		targets[k] = v:Name()
	end
	return string.format(str, unpack(targets))
end

SAdminCon:AddCommand("goto", "tp", function(ply, args)
	if not IsValid(ply) or not args[1] then return false, "Missing arguements" end
	local target, err = checktarget(findplayer(args[1]))
	if target == ply then return false, "You can't goto yourself!" end
	if not target then return false, err end

	ply:SetPos(target:GetPos())
	ActivateNoCollision(ply, 1)
	return targetString("%s teleported to %s", ply, target)
end, "Teleports you to a player", "<player>")

SAdminCon:AddCommand("bring", "tp", function(ply, args)
	if not IsValid(ply) or not args[1] then return false, "Missing arguements" end
	local target, err = checktarget(findplayer(args[1]))
	if target == ply then return false, "You can't bring yourself!" end
	if not target then return false, err end

	target:SetPos(ply:GetPos())
	ActivateNoCollision(target, 1)
	return targetString("%s teleported %s to them", ply, target)
end, "Brings a player to you", "<player>")

SAdminCon:AddCommand("tp", "tp", function(ply, args)
	if not args[1] or not args[2] then return false, "Missing arguements" end
	local target1, err = checktarget(findplayer(args[1]))
	local target2, err2 = checktarget(findplayer(args[2]))
	if not target1 then return false, err end
	if not target2 then return false, err2 end

	target1:SetPos(target2:GetPos())
	ActivateNoCollision(target1, 1)
	return targetString("%s teleported %s to %s", ply, target1, target2)
end, "Teleports a player to another player", "<player> <player>")


SAdminCon:AddCommand("kick", "admin", function(ply, args, argstr)
	local target, err = checktarget(findplayer(args[1]))
	if not target then return false, err end
	if not ply:IsSuperAdmin() and target:IsSuperAdmin() then return false, "You can't kick someone higher than you!" end
	if target:IsListenServerHost() then return false, "You can't kick the server host!" end

	local reason = argstr:sub(#args[1] + 1):Trim()
	reason = reason ~= "" and reason or "Reason not given"
	target:Kick("You were kicked from the server for:\n" .. reason)

	return targetString("%s kicked %s from the server for: ", ply, target) .. reason
end, "Kicks a player from the server", "<player> [reason]")

local suffixes = {
	["d"] = 60 * 24,
	["w"] = 60 * 24 * 7,
	["h"] = 60,
	["m"] = 60 * 24 * 30,
	["y"] = 60 * 24 * 365,
}

local words = {
	["d"] = "day(s)",
	["w"] = "week(s)",
	["h"] = "hour(s)",
	["m"] = "month(s)",
	["y"] = "year(s)",
}

SAdminCon:AddCommand("ban", "admin", function(ply, args, argstr)
	local target, err = checktarget(findplayer(args[1]))
	if not target then return false, err end
	if not ply:IsSuperAdmin() and target:IsSuperAdmin() then return false, "You can't ban someone higher than you!" end
	if target:IsListenServerHost() then return false, "You can't ban the server host!" end

	local time = tonumber(args[2])
	local suffix, mult, word = args[2]:sub(-1), 1, "minutes"
	if not tonumber(suffix) then
		time = tonumber(args[2]:sub(0, -1))
		mult = suffixes[suffix]
		if not mult then return false, "Invalid time suffix" end
		word = words[suffix]
	end

	if not isnumber(time) then
		return false, "Invalid time length"
	end

	local calctime = time * mult

	local reason = argstr:sub(#args[1] + #args[2] + 1):Trim()
	reason = reason ~= "" and reason or "Not given"
	target:Ban(calctime, false)
	target:Kick("You were banned from the server for " .. time .. " " .. word .. ".\nReason: " .. reason)

	return targetString("%s banned %s from the server for ", ply, target) .. time .. " " .. word .. ". Reason: " .. reason

end, "Bans a player for and can be removed with $unbanid", "<player> <minutes or suffix of h, d, w, m, y (ex. 40w = 40 weeks), 0 for permanent> [reason]")

SAdminCon:AddCommand("unbanid", "admin", function(ply, args, argstr)
	if util.SteamIDTo64(argstr or "") == "0" then
		return false, "Invalid SteamID"
	end

	RunConsoleCommand("removeid", argstr)

	return targetString("%s unbanned SteamID ", ply) .. argstr
end)

SAdminCon:AddCommand("banid", "admin", function(ply, args, argstr)
	if util.SteamIDTo64(args[1] or "") == "0" then
		return false, "Invalid SteamID"
	end

	if not args[2] then return end

	local time = tonumber(args[2])
	local suffix, mult, word = args[2]:sub(-1), 1, "minutes"
	if not tonumber(suffix) then
		time = tonumber(args[2]:sub(0, -1))
		mult = suffixes[suffix]
		if not mult then return false, "Invalid time suffix" end
		word = words[suffix]
	end

	if not isnumber(time) then
		return false, "Invalid time length"
	end

	local calctime = time * mult
	local tply = player.GetBySteamID(args[1])

	RunConsoleCommand("banid", args[1], calctime)
	if tply then
		tply:Kick("You were banned from the server.")
	end

	return targetString("%s banned SteamID ", ply) .. args[1] .. " for " .. time .. " " .. word .. "."
end)



SAdminCon:AddCommand("restrict", "superadmin", function(ply, args)
	if not args[1] then return false, "Missing arguements" end
	SAdminCon:SetStatus(args[1], true)

	return targetString("%s restricted ", ply) .. args[1]
end, "Restricts an entity or tool by class name", "<class name>", "res")

SAdminCon:AddCommand("unrestrict", "superadmin", function(ply, args)
	if not args[1] then return false, "Missing arguements" end
	SAdminCon:SetStatus(args[1], false)

	return targetString("%s unrestricted ", ply) .. args[1]
end, "Unrestricts an entity or tool by class name", "<class name>", "unr")


SAdminCon:AddCommand("restricttool", "superadmin", function(ply, args)
	if not IsValid(ply) or not IsValid(ply:GetActiveWeapon()) or ply:GetActiveWeapon():GetClass() ~= "gmod_tool" then return false, "Not holding a toolgun!" end
	local tool = ply:GetInfo("gmod_toolmode")
	SAdminCon:SetStatus(tool, true)

	return targetString("%s restricted ", ply) .. tool
end, "Restricts the current tool you have out", "(must have toolgun out)", "rtool")

SAdminCon:AddCommand("unrestricttool", "superadmin", function(ply, args)
	if not IsValid(ply) or not IsValid(ply:GetActiveWeapon()) or ply:GetActiveWeapon():GetClass() ~= "gmod_tool" then return false, "Not holding a toolgun!" end
	local tool = ply:GetInfo("gmod_toolmode")
	SAdminCon:SetStatus(tool, false)

	return targetString("%s unrestricted ", ply) .. tool
end, "Unrestricts the current tool you have out", "(must have toolgun out)", "unrtool")

function SAdminCon.SaveUser(steamid, name, group)

end

SAdminCon:AddCommand("promote", "superadmin", function(ply, args)
	local target, err = checktarget(findplayer(args[1]))
	if not target then return false, err end

	if not target:IsAdmin() then
		target:SetUserGroup("admin")
	elseif not target:IsSuperAdmin() then
		target:SetUserGroup("superadmin")
	end
end, "Promotes a player to admin, and then to a superadmin. Resets on join.", "<player>")

SAdminCon:AddCommand("demote", "superadmin", function(ply, args)
	local target, err = checktarget(findplayer(args[1]))
	if not target then return false, err end

	if target:IsSuperAdmin() then
		target:SetUserGroup("admin")
	elseif target:IsAdmin() then
		target:SetUserGroup("user")
	end
end, "Demotes a player to admin, and then to a user. Resets on join.", "<player>")

SAdminCon:AddCommand("noclip", "admin", function(ply, args)
	local target = checktarget(findplayer(args[1]))
	if not target then target = ply end

	if target:GetMoveType() == MOVETPE_NOCLIP then
		target:SetMoveType(MOVETYPE_WALK)
	else
		target:SetMoveType(MOVETYPE_NOCLIP)
	end
end, "Enables noclip for a player", "[player (no player defaults to user)]")

SAdminCon.PrintHelp = function()
	local str = "---SAdminCon Commands---\n"
	for k, v in SortedPairsByMemberValue(Commands, "cat") do
		str = str .. SAdminCon.GetPrefix() .. v.name .. " " .. (v.input or "(empty)") .. " - " .. (v.desc or "No help text") .. " (" .. v.cat .. ")\n"
		if v.short then
			str = str .. "Alias: " .. SAdminCon.GetPrefix() .. v.short .. "\n"
		end
		str = str .. "\n"
	end
	print(str)
end

SAdminCon:AddCommand("help", "general", function(ply, args)
	if IsValid(ply) then
		ply:SendLua("SAdminCon.PrintHelp()")
		ply:ChatPrint("Printed help text to console!")
	else
		SAdminCon.PrintHelp()
	end
end, "Prints the list of commands in the players console")