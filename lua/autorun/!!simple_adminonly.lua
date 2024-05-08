SAdminCon = SAdminCon or {}
SAdminCon.Entities = SAdminCon.Entities or {}

-- Override this if you want to 
function SAdminCon:CanEdit(ply)
	return ply:IsListenServerHost() or ply:IsSuperAdmin()
end

function SAdminCon:IsAdmin(ply)
	return ply:IsListenServerHost() or ply:IsAdmin()
end
----------

SAdminCon.hide_convar = CreateConVar("sac_hide", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "1=Hide admin only stuff")
SAdminCon.tp_convar = CreateConVar("sac_tp_perms", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "0=Admins Only  1=Anyone can use Goto  2=Anyone can use every TP command")
SAdminCon.announce_convar = CreateConVar("sac_announce", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "0=Commands are announced to everyone  1=Commands are announced to user")
SAdminCon.prefix_convar = CreateConVar("sac_prefix", "$", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Sets the prefix, can be multiple characters but shouldn't contain spaces")

function SAdminCon.GetPrefix()
	return SAdminCon.prefix_convar:GetString()
end

local types = {
	["npc"] = "NPC",
	["weapon"] = "Weapon",
	["entity"] = "SpawnableEntities",
	["vehicle"] = "Vehicles",
}

if SERVER then
	util.AddNetworkString("SAdminCon_Setting")
	util.AddNetworkString("SAdminCon_Update")

	function SAdminCon:Save()
		local str = util.TableToJSON(self.Entities, true)
		file.Write("spawnac.txt", str)
	end

	function SAdminCon:Load()
		local str = file.Read("spawnac.txt")
		self.Entities = util.JSONToTable(str or "") or {}
		self:UpdateAll()
	end

	function SAdminCon:UpdateAll()
		for k, v in pairs(self.Entities) do
			self:Update(k, v)
		end
	end

	function SAdminCon:Update(k, v)
		local l = scripted_ents.GetStored(k) or weapons.GetStored(k)
		if l then
			l.s_AdminOnly = l.s_AdminOnly or l.AdminOnly
			l.AdminOnly = v
		end

		for _, cat in pairs(types) do
			local b = list.GetForEdit(cat)[k]
			if b then
				b.s_AdminOnly = b.s_AdminOnly or b.AdminOnly
				b.AdminOnly = v
			end
		end
	end

	function SAdminCon:BroadcastUpdate(ent, status)
		net.Start("SAdminCon_Update")
			net.WriteString(ent)
			net.WriteBool(status)
		net.Broadcast()
	end

	function SAdminCon:SetStatus(ent, status)
		self.Entities[ent] = status
		self:Update(ent, status)
		self:BroadcastUpdate(ent, status)
		self:Save()
	end

	function SAdminCon:SendToPlayer(ply)
		local e = self.Entities
		net.Start("SAdminCon_Setting")
			net.WriteUInt(table.Count(e), 16)
			for k, v in pairs(e) do
				net.WriteString(k)
				net.WriteBool(v)
			end
		net.Send(ply)
	end

	concommand.Add("_requestSAdminCon", function(ply)
		if ply.SAdminCon and ply.SAdminCon > CurTime() then return end
		ply.SAdminCon = CurTime() + 5
		SAdminCon:SendToPlayer(ply)
	end)

	net.Receive("SAdminCon_Setting", function(_, ply)
		if not SAdminCon:CanEdit(ply) then return end
		local k, v = net.ReadString(), net.ReadBool()
		SAdminCon:SetStatus(k, v)
	end)

	function SAdminCon.SpawnCheck(ply, str)
		if not SAdminCon:IsAdmin(ply) and SAdminCon.Entities[str] then
			if not ply.SAC_LastPrint or (ply.SAC_LastPrint and ply.SAC_LastPrint < CurTime()) then
				ply:ChatPrint("[SAC] The ent \"" .. str .. "\" is restricted!")
				ply.SAC_LastPrint = CurTime() + 1
			end
			return false
		end
	end

	function SAdminCon.ToolCheck(ply, _, str)
		if not SAdminCon:IsAdmin(ply) and SAdminCon.Entities[str] then
			if not ply.SAC_LastPrint or (ply.SAC_LastPrint and ply.SAC_LastPrint < CurTime()) then
				ply:ChatPrint("[SAC] The tool \"" .. str .. "\" is restricted!")
				ply.SAC_LastPrint = CurTime() + 1
			end
			return false
		end
	end

	hook.Add("PlayerGiveSWEP", "!!SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnSENT", "!!SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnSWEP", "!!SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnNPC", "!!SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnVehicle", "!!SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("CanTool", "!!SAdminCon_Spawn", SAdminCon.ToolCheck)
	hook.Add("InitPostEntity", "!!SAdminCon_Load", function() SAdminCon:Load() end)

	-- bad inheritance priortizes truthy values because gmod is silly
	scripted_ents.s_GetMember = scripted_ents.s_GetMember or scripted_ents.GetMember
	function scripted_ents.GetMember(str, mem)
		if mem == "AdminOnly" then
			local t = scripted_ents.GetStored(str)
			if t and t.AdminOnly ~= nil then
				return t.AdminOnly
			end
		end

		return scripted_ents.s_GetMember(str, mem)
	end
else
	local done = {}
	function SAdminCon:TranslateListName(str, type)
		if done[str] ~= nil then return done[str] end

		local l = list.Get(types[type])
		local obj = l[str]

		if not l[str] then
			done[str] = str
			return str
		end

		local class = obj.ClassName or obj.Class
		done[str] = class
		return class
	end

	function SAdminCon:GetStatusPanel(pnl)
		local sp, ty = pnl:GetSpawnName(), pnl:GetContentType()
		if not sp or not ty or not types[ty] then return end
		return self.Entities[self:TranslateListName(sp, ty)]
	end

	function SAdminCon:GetStatus(class)
		return self.Entities[class]
	end

	function SAdminCon:SendUpdate(ent, status)
		net.Start("SAdminCon_Setting")
			net.WriteString(ent)
			net.WriteBool(status)
		net.SendToServer()
	end

	function SAdminCon.UpdateContentIcon()
		local tab = vgui.GetControlTable("ContentIcon")
		function tab:GetAdminOnly()
			local stat = SAdminCon:GetStatusPanel(self)
			return stat == nil and self.m_bAdminOnly or stat
		end

		spawnmenu.s_CreateContentIcon = spawnmenu.s_CreateContentIcon or spawnmenu.CreateContentIcon
		function spawnmenu.CreateContentIcon(type, pnl, data)
			local ic = spawnmenu.s_CreateContentIcon(type, pnl, data)
			if not types[type] then return ic end

			if IsValid(ic) then
				ic.s_OpenMenuExtra = ic.s_OpenMenuExtra or ic.OpenMenuExtra
				ic.Think = function(p)
					if p:GetAdminOnly() and SAdminCon.hide_convar:GetBool() and not p.OldSizeX and not SAdminCon:IsAdmin(LocalPlayer()) then
						p.OldSizeX, p.OldSizeY = p:GetSize()
						p:SetSize(0, 0)
						p:SetVisible(false)
					end
				end

				function ic:OpenMenuExtra(menu)
					self:s_OpenMenuExtra(menu)
					if not SAdminCon:CanEdit(LocalPlayer()) then return end

					menu:AddSpacer()
					if self:GetSpawnName() == "__dummy" then return end
					if not self:GetAdminOnly() then
						menu:AddOption("Restrict to Admins", function()
							SAdminCon:SendUpdate(SAdminCon:TranslateListName(self:GetSpawnName(), self:GetContentType()), true)
						end):SetIcon("icon16/delete.png")
					else
						menu:AddOption("Unrestrict for Everyone", function()
							SAdminCon:SendUpdate(SAdminCon:TranslateListName(self:GetSpawnName(), self:GetContentType()), false)
						end):SetIcon("icon16/add.png")
					end
				end
			end
			return ic
		end
	end

	net.Receive("SAdminCon_Setting", function(_, ply)
		local e = {}
		local len = net.ReadUInt(16)
		for i = 1, len do
			local k, v = net.ReadString(), net.ReadBool()
			e[k] = v
		end
		SAdminCon.Entities = e
	end)

	net.Receive("SAdminCon_Update", function(_, ply)
		local k, v = net.ReadString(), net.ReadBool()
		SAdminCon.Entities[k] = v
		if SAdminCon.hide_convar:GetBool() and not SAdminCon:IsAdmin(LocalPlayer()) then
			timer.Create("UpdateSpawnmenu", 15, 1, function()
				RunConsoleCommand("spawnmenu_reload")
			end)
		end
	end)

	hook.Add("PreGamemodeLoaded", "SAdminCon_UpdateIcon", SAdminCon.UpdateContentIcon)
	hook.Add("SpawnMenuOpen", "SAdminCon_Request", function()
		if SAdminCon.First then return end
		RunConsoleCommand("_requestSAdminCon")
		SAdminCon.First = true
	end)

	-- hook.Add("AddToolMenuCategories", "SAC_Category", function()
	-- 	spawnmenu.AddToolCategory("Utilities", "SAC", "#SAC" )
	-- end)

	-- hook.Add("PopulateToolMenu", "SAC_BuildMenu", function()
	-- 	spawnmenu.AddToolMenuOption("Utilities", "SAC", "SAC_Menu", "#Simple Admin Control", "", "", function(panel)
	-- 		panel:ClearControls()
	-- 		panel:NumSlider( "Gravity", "sv_gravity", 0, 600 )
	-- 	end)
	-- end)

	local shield = Material("icon16/shield.png")
	hook.Add("PostReloadToolsMenu", "SAC_LoadToolMenu", function()
		timer.Simple(0.1, function()
			local tp = g_SpawnMenu.ToolMenu.ToolPanels[1]
			local tlist = tp.List
			if not IsValid(tp) or not IsValid(tlist) then return end

			for _, cat in pairs(tlist.pnlCanvas:GetChildren()) do
				for k, v in pairs(cat:GetChildren()) do
					if v.ClassName == "DCategoryHeader" then continue end

					v.s_DoRightClick = v.s_DoRightClick or v.DoRightClick
					function v:DoRightClick(w, h)
						if not SAdminCon:CanEdit(LocalPlayer()) and self.s_DoRightClick then self:s_DoRightClick() return end

						local menu = DermaMenu()

						if self._Paint and self.s_DoRightClick then -- (favorite tools plugin)
							menu:AddOption("Toggle Favorite", function()
								self:s_DoRightClick()
							end):SetIcon("icon16/heart.png")
						end

						if not self:GetAdminOnly() then
							menu:AddOption("Restrict to Admins", function()
								SAdminCon:SendUpdate(self.Name, true)
							end):SetIcon("icon16/delete.png")
						else
							menu:AddOption("Unrestrict for Everyone", function()
								SAdminCon:SendUpdate(self.Name, false)
							end):SetIcon("icon16/add.png")
						end

						menu:Open()
					end

					function v:GetAdminOnly()
						return SAdminCon:GetStatus(self.Name)
					end

					v.s_Paint = v.s_Paint or v.Paint
					v.s_Think = v.s_Think or v.Think
					function v:Think()
						if v.s_Think then v:s_Think() end

						local ply = LocalPlayer()
						if SAdminCon.hide_convar:GetBool() and self:GetAdminOnly() and not self.ChangeStatus and not SAdminCon:IsAdmin(ply)  then
							self:SetVisible(false)
							self.ChangeStatus = true
							tlist.pnlCanvas:InvalidateLayout()
							cat:InvalidateLayout()
							return
						end
					end

					function v:Paint(w, h)
						local ret = self:s_Paint(w, h)
						if self:GetAdminOnly() then
							surface.SetMaterial(shield)
							surface.SetDrawColor(Color(255, 255, 255))
							surface.DrawTexturedRect(w - 6, h * 0.5 - 5.5, 11, 11)
						end
						return ret
					end
				end
			end
		end)
	end)
end

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

		return cmd.func(ply, args, argstr or "")
	end

	hook.Add("PlayerSay", "SAC_ONCHAT", function(ply, str)
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


SAdminCon.Bans = {}
SAdminCon:AddCommand("kickban", "admin", function(ply, args, argstr)
	local target, err = checktarget(findplayer(args[1]))
	if not target then return false, err end
	if not ply:IsSuperAdmin() and target:IsSuperAdmin() then return false, "You can't kick someone higher than you!" end
	if target:IsListenServerHost() then return false, "You can't kick the server host!" end

	local reason = argstr:sub(#args[1] + 1):Trim()
	reason = reason ~= "" and reason or "Reason not given"
	target:Kick("You were banned from the server for:\n" .. reason)
	SAdminCon.Bans[target:SteamID64()] = reason

	return targetString("%s kickbanned %s from the server for: ", ply, target) .. reason

end, "Kicks and bans a player for the remainder of the game session. Will not be saved and can be removed with sac_cleartempbans", "<player> [reason]", "kb")

concommand.Add("sac_cleartempbans", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then
		return ply:ChatPrint("You need to be a Superadmin to clear bans!")
	end
	print("[SAC] Bans Manually Cleared by " .. (IsValid(ply) and ply:Name() or "Console"))
	SAdminCon.Bans = {}
end)

hook.Add("CheckPassword", "SAC_BanPlayer", function(id64, ip)
	if SAdminCon.Bans[id64] then
		return false, "You are temporarily banned from the server for:\n" .. SAdminCon.Bans[id64]
	end
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

hook.Run("SAC_LOADED")