local types = SAdminCon.types
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
	net.Start("SAdminCon_Update")
	net.WriteString(ent)
	net.WriteBool(status)
	net.SendToServer()
end

function SAdminCon:SendTable(e)
	net.Start("SAdminCon_Setting")
	net.WriteUInt(table.Count(e), 16)

	for k, v in pairs(e) do
		net.WriteString(k)
		net.WriteBool(v)
	end

	net.SendToServer()
end

local shield = Material("icon16/shield.png")
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

	--/ properties
	local List = properties.List

	local function AddToggleOption(data, menu, ent, ply, tr)
		if not menu.ToggleSpacer then
			menu.ToggleSpacer = menu:AddSpacer()
			menu.ToggleSpacer:SetZPos(500)
		end

		local option = menu:AddOption(data.MenuLabel, function()
			data:Action(ent, tr)
		end)

		option:SetChecked(data:Checked(ent, ply))
		option:SetZPos(501)

		return option
	end

	local function AddOption(data, menu, ent, ply, tr)
		if data.Type == "toggle" then return AddToggleOption(data, menu, ent, ply, tr) end

		if data.PrependSpacer then
			menu:AddSpacer()
		end

		local option = menu:AddOption(data.MenuLabel, function()
			data:Action(ent, tr)
		end)

		if data.MenuIcon then
			option:SetImage(data.MenuIcon)
		end

		if data.MenuOpen then
			data.MenuOpen(data, option, ent, tr)
		end

		return option
	end

	function properties.OpenEntityMenu(ent, tr)
		local menu = DermaMenu()

		for k, v in SortedPairsByMemberValue(List, "Order") do
			if not v.Filter then continue end
			if not v:Filter(ent, LocalPlayer()) then continue end
			local option = AddOption(v, menu, ent, LocalPlayer(), tr)

			if v.OnCreate then
				v:OnCreate(menu, option)
			end

			local name = v.InternalName
			function option:DoRightClick()
				if name == "editentity" then return end
				SAdminCon:SendUpdate(name, not SAdminCon:GetStatus(name))
			end

			option.OPaint = option.Paint
			function option:Paint(w, h)
				self:OPaint(w, h)
				if SAdminCon:GetStatus(name) then
					surface.SetMaterial(shield)
					surface.SetDrawColor(Color(255, 255, 255))
					surface.DrawTexturedRect(w - 14, h * 0.5 - 5.5, 11, 11)
				end
			end
		end

		menu:Open()

		return menu
	end
end

net.Receive("SAdminCon_Setting", function(_, ply)
	local e = SAdminCon.Entities
	local len = net.ReadUInt(16)

	for i = 1, len do
		local k, v = net.ReadString(), net.ReadBool()
		e[k] = v
	end
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

local ndone = {}

local function modify_node(node)
	if node and ndone[node] then return end
	if not IsValid(node) then ndone[node or false] = true return end
	node.DoRightClick = function(self)
		if not SAdminCon:CanEdit(LocalPlayer()) then return end
		local pnl = self.PropPanel or self.ViewPanel
		if not IsValid(pnl) then return end
		local menu = DermaMenu()

		menu:AddOption("Restrict Category", function()
			local tbl = {}

			for k, v in pairs(pnl:ContentsToTable()) do
				if v.admin then continue end
				tbl[SAdminCon:TranslateListName(v.spawnname, v.type)] = true
			end

			SAdminCon:SendTable(tbl)
		end):SetIcon("icon16/delete.png")

		menu:AddOption("Unrestrict Category", function()
			local tbl = {}

			for k, v in pairs(pnl:ContentsToTable()) do
				if not v.admin then continue end
				tbl[SAdminCon:TranslateListName(v.spawnname, v.type)] = false
			end

			SAdminCon:SendTable(tbl)
		end):SetIcon("icon16/add.png")

		menu:Open()
	end

	ndone[node] = true

	if node.GetChildNodes then
		for k, v in pairs(node:GetChildNodes()) do
			modify_node(node)
		end
	end
end

local function node_settings(content, tree, node)
	if not IsValid(tree) then return end
	timer.Simple(0.1, function()
		local root = tree.Root and tree:Root() or tree.GetRoot and tree:GetRoot()
		if not IsValid(root) then return end
		for k, v in pairs(root:GetChildNodes()) do
			modify_node(v)
		end
	end)
end

hook.Add("PopulateVehicles", "SAC_Node", node_settings)
hook.Add("PopulateWeapons", "SAC_Node", node_settings)
hook.Add("PopulateEntities", "SAC_Node", node_settings)
hook.Add("PopulateNPCs", "SAC_Node", node_settings)

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
					if not SAdminCon:CanEdit(LocalPlayer()) and self.s_DoRightClick then
						self:s_DoRightClick()
						return
					end

					local menu = DermaMenu()

					-- (favorite tools plugin)
					if self._Paint and self.s_DoRightClick then
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
					if v.s_Think then
						v:s_Think()
					end

					local ply = LocalPlayer()

					if SAdminCon.hide_convar:GetBool() and self:GetAdminOnly() and not self.ChangeStatus and not SAdminCon:IsAdmin(ply) then
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