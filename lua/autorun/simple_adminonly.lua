SAdminCon = SAdminCon or {}
SAdminCon.Entities = SAdminCon.Entities or {}

-- Override this if you want to 
function SAdminCon:CanEdit(ply)
	return ply:IsListenServerHost() or ply:IsSuperAdmin()
end
----------

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
		if not ply:IsAdmin() and SAdminCon.Entities[str] then return false end
	end

	hook.Add("PlayerGiveSWEP", "SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnSENT", "SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnSWEP", "SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnNPC", "SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("PlayerSpawnVehicle", "SAdminCon_Spawn", SAdminCon.SpawnCheck)
	hook.Add("InitPostEntity", "SAdminCon_Load", function() SAdminCon:Load() end)

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
				function ic:OpenMenuExtra(menu)
					self:s_OpenMenuExtra(menu)
					if not SAdminCon:CanEdit(LocalPlayer()) then return end

					menu:AddSpacer()
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
	end)

	hook.Add("PreGamemodeLoaded", "SAdminCon_UpdateIcon", SAdminCon.UpdateContentIcon)
	hook.Add("SpawnMenuOpen", "SAdminCon_Request", function()
		if SAdminCon.First then return end
		RunConsoleCommand("_requestSAdminCon")
		SAdminCon.First = true
	end)
end