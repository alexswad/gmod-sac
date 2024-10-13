local types = SAdminCon.types
SAdminCon.Categories = {
	"entity",
	"weapon",
	"npc",
	"vehicle",
	"tool",
	"prop",
}

local tools

local cache = {}
function SAdminCon:GetCategory(name)
	tools = tools or weapons.GetStored("gmod_tool") and weapons.GetStored("gmod_tool").Tool
	if cache[name] then return cache[name] end

	if weapons.GetStored(name) then
		cache[name] = "weapon"
		return "weapon"
	end

	for cat, type in pairs(types) do
		local b = list.GetForEdit(type)[name]
		if b then
			cache[name] = cat
			return cat
		end
	end

	if scripted_ents.GetStored(name) then
		cache[name] = "entity"
		return "entity"
	end

	if tools[name] then
		cache[name] = "tool"
		return "tool"
	end

	if util.IsValidProp(name) or util.IsValidRagdoll(name) then
		cache[name] = "prop"
		return "prop"
	end

	cache[name] = "other"
	return "other"
end

function SAdminCon:CheckWL(name)
	local cat = self:GetCategory(name)
	return self.WL[cat] and self.WL[cat]:GetBool() or false
end

SAdminCon.WL = {}
for k, v in pairs(SAdminCon.Categories) do
	SAdminCon.WL[v] = CreateConVar("sac_wl_" .. v, "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
end