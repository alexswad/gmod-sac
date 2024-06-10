local types = SAdminCon.types
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
		if l.s_AdminOnly == nil then l.s_AdminOnly = l.AdminOnly end
		l.AdminOnly = v
	end

	for _, cat in pairs(types) do
		local b = list.GetForEdit(cat)[k]
		if b then
			if b.s_AdminOnly == nil then b.s_AdminOnly = b.AdminOnly end
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

function SAdminCon:BroadcastTable(tbl)
	local e = tbl or self.Entities
	net.Start("SAdminCon_Setting")
		net.WriteUInt(table.Count(e), 16)
		for k, v in pairs(e) do
			net.WriteString(k)
			net.WriteBool(v)
		end
	net.Broadcast()
end

function SAdminCon:SetStatus(ent, status)
	self.Entities[ent] = status
	self:Update(ent, status)
	self:BroadcastUpdate(ent, status)
	self:Save()
end

function SAdminCon:SendToPlayer(ply, tbl)
	local e = tbl or self.Entities
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

net.Receive("SAdminCon_Update", function(_, ply)
	if not SAdminCon:CanEdit(ply) then return end
	local k, v = net.ReadString(), net.ReadBool()
	SAdminCon:SetStatus(k, v)
end)

net.Receive("SAdminCon_Setting", function(_, ply)
	if not SAdminCon:CanEdit(ply) then return end
	local e = {}
	local len = net.ReadUInt(16)
	for i = 1, len do
		local k, v = net.ReadString(), net.ReadBool()
		e[k] = v
	end
	SAdminCon:BroadcastTable(e)

	for k, v in pairs(e) do
		SAdminCon.Entities[k] = v
	end
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

net.Receive( "properties", function( len, client )
	if not IsValid(client) then return end

	local name = net.ReadString()
	if not name then return end

	local prop = properties.List[name]
	if not prop then return end
	if not prop.Receive then return end

	if SAdminCon.Entities[name] then
		if not client.SAC_LastPrint or (client.SAC_LastPrint and client.SAC_LastPrint < CurTime()) then
			client:ChatPrint("[SAC] The property \"" .. name .. "\" is restricted!")
			client.SAC_LastPrint = CurTime() + 1
		end
		return
	end

	prop:Receive(len, client)
end)

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