SAdminCon = SAdminCon or {}
SAdminCon.Entities = SAdminCon.Entities or {}
SAdminCon.Prefix = "$"

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
		if not v and SAdminCon.hide_convar:GetBool() and not SAdminCon:IsAdmin(LocalPlayer()) then
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

	hook.Add("AddToolMenuCategories", "SAC_Category", function()
		spawnmenu.AddToolCategory("Utilities", "SAC", "#SAC" )
	end)

	hook.Add("PopulateToolMenu", "SAC_BuildMenu", function()
		spawnmenu.AddToolMenuOption("Utilities", "SAC", "SAC_Menu", "#Simple Admin Control", "", "", function(panel)
			panel:ClearControls()
			panel:NumSlider( "Gravity", "sv_gravity", 0, 600 )
		end)
	end)

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

function SAdminCon:RunCommand(ply, cmd)
	if isstring(cmd) then cmd = CommandLookup[cmd] end
	if IsValid(ply) then
		if cmd.cat == "tp" then
			local tp = self.tp_convar:GetInt()
			if tp == 0 and not SAdminCon:IsAdmin(ply) then
				return
			elseif tp == 1 and cmd.name ~= "goto" then
				return
			end
		elseif cmd.cat == "admin" and not SAdminCon:IsAdmin(ply) then
			return
		elseif cmd.cat == "superadmin" and not SAdminCon:CanEdit(ply) then
			return
		end
	end
end

SAdminCon:AddCommand("goto", "tp", function(ply, args)

end, "Teleports you to a player", "<player>")

SAdminCon:AddCommand("bring", "tp", function(ply, args)

end, "Brings a player to you", "<player>")

SAdminCon:AddCommand("tp", "tp", function(ply, args)

end, "Teleports a player to another player", "<player> <player>")


SAdminCon:AddCommand("kick", "admin", function(ply, args)

end, "Kicks a player from the server", "<player>")

SAdminCon:AddCommand("kickban", "admin", function(ply, args)

end, "Kicks and bans a player for the remainder of the game session. Will not be saved and can be removed with sac_clearbans", "<player>", "kb")


SAdminCon:AddCommand("restrict", "superadmin", function(ply, args)

end, "Restricts an entity or tool by class name", "<class name>", "res")

SAdminCon:AddCommand("unrestrict", "superadmin", function(ply, args)

end, "Unrestricts an entity or tool by class name", "<class name>", "unr")


SAdminCon:AddCommand("restricttool", "superadmin", function(ply, args)

end, "Restricts the current tool you have out", "(must have toolgun out)", "rtool")

SAdminCon:AddCommand("unrestricttool", "superadmin", function(ply, args)

end, "Unrestricts the current tool you have out", "(must have toolgun out)", "unrtool")


SAdminCon:AddCommand("promote", "superadmin", function(ply, args)

end, "Promotes a player to admin, and then to a superadmin. Saved in data/settings/users.txt", "<player>")

SAdminCon:AddCommand("demote", "superadmin", function(ply, args)

end, "Demotes a player to admin, and then to a user. Saved in data/settings/users.txt", "<player>")

hook.Run("SAC_LOADED")