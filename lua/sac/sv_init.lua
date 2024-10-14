local types = SAdminCon.types
util.AddNetworkString("SAdminCon_Setting")
util.AddNetworkString("SAdminCon_Update")
util.AddNetworkString("SAdminCon_Data")

file.CreateDir("sac")
SAdminCon.preset_convar = CreateConVar("sac_preset", "default")

function SAdminCon:Save()
	local str = util.TableToJSON(self.Entities, true)
	file.Write("sac/default.json", str)
end

function SAdminCon:Load()
	local str = file.Read("sac/default.json")
	self.Entities = util.JSONToTable(str or "") or {}
	self:UpdateAll()
end

function SAdminCon:UpdateAll()
	for k, v in pairs(self.Entities) do
		self:Update(k, v)
	end
end

function SAdminCon:GetStatus(class)
	return tobool(self.Entities[class]) ~= self:CheckWL(class)
end

function SAdminCon:Update(k, v)

	local l = scripted_ents.GetStored(k) or weapons.GetStored(k)
	if l then
		if l.s_AdminOnly == nil then l.s_AdminOnly = (l.AdminOnly or false) end
		l.AdminOnly = v ~= self:CheckWL(k)
	end

	local ret = false
	for key, cat in pairs(types) do
		local b = list.GetForEdit(cat)[k]
		if b then
			if b.s_AdminOnly == nil then b.s_AdminOnly = (b.AdminOnly or false) end
			b.AdminOnly = v ~= self:CheckWL(k)
			if b.s_AdminOnly == v and not (b.s_AdminOnly and self:CheckWL(k)) then
				SAdminCon.Entities[k] = nil
				return false
			end
			ret = true
		end
	end
	if ret then return end

	if v == false then
		SAdminCon.Entities[k] = nil
		return false
	end
end

function SAdminCon:BroadcastUpdate(ent, status)
	net.Start("SAdminCon_Update", true)
		net.WriteString(ent)
		net.WriteUInt(status, 3)
	net.Broadcast()
end

local pmax = 400

local function partify(tbl)
	if table.Count(tbl) < pmax then return tbl end
	local parts = math.ceil(table.Count(tbl) / pmax)
	local ntbl = {}
	ntbl.parts = parts

	local count = 0
	for k, v in pairs(tbl) do
		count = count + 1

		local cpart = math.ceil(count / pmax)
		ntbl[cpart] = ntbl[cpart] or {}
		ntbl[cpart][k] = v
	end
	return ntbl
end

local function send_part(tbl, tparts, part, ply, clear)
	net.Start("SAdminCon_Data", true)
		net.WriteBool(clear)
		net.WriteUInt(tparts, 6)
		net.WriteUInt(part, 6)
		net.WriteUInt(table.Count(tbl), 16)

		for k, v in pairs(tbl) do
			net.WriteString(k)
			net.WriteUInt(isnumber(v) and v or v and 1 or 0, 3)
		end

	if IsValid(ply) then
		net.Send(ply)
		return true
	elseif ply == nil then
		net.Broadcast()
		return true
	end
end

SAdminCon.DataTimers = {}

function SAdminCon:DestroyDTimers()
	for k, v in pairs(self.DataTimers) do
		timer.Remove(k)
	end
	self.DataTimers = {}
end

function SAdminCon:SendTable(tbl, ply, clear)
	local name = "SAdminUpdate_" .. (IsValid(ply) and ply:SteamID() or "Broadcast")

	if not IsValid(ply) and clear then
		self:DestroyDTimers()
	end

	tbl = partify(tbl)
	if not tbl.parts then
		send_part(tbl, 1, 1, ply, clear)
		return
	end

	local cpart = 0
	timer.Create(name, 1, tbl.parts, function()
		cpart = cpart + 1
		send_part(tbl[cpart], tbl.parts, cpart, ply, clear)
	end)
	self.DataTimers[name] = true
end

function SAdminCon:SetStatus(ent, status)
	self.Entities[ent] = status
	if self:Update(ent, status) == false then
		self:BroadcastUpdate(ent, 2)
	else
		self:BroadcastUpdate(ent, status and 1 or 0)
	end
	self:Save()
end

concommand.Add("_requestSAdminCon", function(ply)
	if ply.SAdminCon and ply.SAdminCon > CurTime() then return end
	ply.SAdminCon = CurTime() + 5
	SAdminCon:SendTable(SAdminCon.Entities, ply, true)
end)

net.Receive("SAdminCon_Update", function(_, ply)
	if not SAdminCon:CanEdit(ply) then return end
	local k, v = net.ReadString(), net.ReadBool()
	SAdminCon:SetStatus(k, v ~= SAdminCon:CheckWL(k))
end)

net.Receive("SAdminCon_Data", function(_, ply)
	if not SAdminCon:CanEdit(ply) then return end
	local e = {}
	local len = net.ReadUInt(16)
	for i = 1, len do
		local k, v = net.ReadString(), net.ReadBool()
		e[k] = v ~= SAdminCon:CheckWL(k)
	end

	for k, v in pairs(e) do
		if SAdminCon:Update(k, v) ~= false then
			SAdminCon.Entities[k] = v
		else
			SAdminCon.Entities[k] = nil
			e[k] = 2
		end
	end

	SAdminCon:SendTable(e)
end)

function SAdminCon.SpawnCheck(ply, str)
	if not SAdminCon:IsAdmin(ply) and SAdminCon:GetStatus(str) then
		if not ply.SAC_LastPrint or (ply.SAC_LastPrint and ply.SAC_LastPrint < CurTime()) then
			ply:ChatPrint("[SAC] The entity \"" .. str .. "\" is restricted!")
			ply.SAC_LastPrint = CurTime() + 1
		end
		return false
	end
end

function SAdminCon.PropCheck(ply, str)
	if not SAdminCon:IsAdmin(ply) and SAdminCon:GetStatus(str) then
		if not ply.SAC_LastPrint or (ply.SAC_LastPrint and ply.SAC_LastPrint < CurTime()) then
			ply:ChatPrint("[SAC] The model \"" .. str .. "\" is restricted!")
			ply.SAC_LastPrint = CurTime() + 1
		end
		return false
	end
end

function SAdminCon.ToolCheck(ply, _, str)
	if not SAdminCon:IsAdmin(ply) and SAdminCon:GetStatus(str) then
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

	if not SAdminCon:IsAdmin(client) and SAdminCon:GetStatus(name) then
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
hook.Add("PlayerSpawnProp", "!!SAdminCon_SpawnProp", SAdminCon.PropCheck)
hook.Add("CanTool", "!!SAdminCon_Spawn", SAdminCon.ToolCheck)
hook.Add("InitPostEntity", "!!SAdminCon_Load", function() SAdminCon:Load() end)
hook.Add("PlayerSetModel", "!!SAdminCon_CheckModel", function(ply)
	timer.Simple(0.1, function()
		if not IsValid(ply) then return end
		local m = player_manager.TranslateToPlayerModelName(ply:GetModel())
		if m and SAdminCon:GetStatus(m) and not SAdminCon:IsAdmin(ply) then
			ply:ChatPrint("[SAC] The playermodel " .. m .. " is restricted!")
			ply:SetModel("models/player/kleiner.mdl")
		end
	end)
end)

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

--Backwards compat
if file.Exists("spawnac.txt", "DATA") then
	local data = file.Read("spawnac.txt")
	file.Write("spawnac.bak.txt", data)
	file.Delete("spawnac.txt")

	file.Write("sac/default.json", data)
end