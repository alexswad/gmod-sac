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
SAdminCon.disable_chat = CreateConVar("sac_disablecommands", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "1=Commands Disabled 0=Commands Enabled")

function SAdminCon.GetPrefix()
	return SAdminCon.prefix_convar:GetString()
end

SAdminCon.types = {
	["npc"] = "NPC",
	["weapon"] = "Weapon",
	["entity"] = "SpawnableEntities",
	["vehicle"] = "Vehicles",
}

AddCSLuaFile("sac/cl_init.lua")
AddCSLuaFile("sac/commands.lua")
AddCSLuaFile("sac/categories.lua")

if SERVER then include("sac/sv_init.lua") end
if CLIENT then include("sac/cl_init.lua") end
include("sac/commands.lua")
include("sac/categories.lua")

hook.Run("SAC_LOADED")