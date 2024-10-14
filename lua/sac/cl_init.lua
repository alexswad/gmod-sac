local types = SAdminCon.types
local done = {}


function SAdminCon:TranslateListName(str, type)
	if done[str] ~= nil then return done[str] end
	local l = list.Get(types[type])
	local obj = l[str]

	if not obj then
		done[str] = str

		return str
	end

	local class = obj.ClassName or obj.Class
	done[str] = class

	return class
end

function SAdminCon:GetStatusPanel(pnl, def)
	local sp, ty = pnl:GetSpawnName(), pnl:GetContentType()
	if not sp or not ty or not types[ty] then return end
	return self:GetStatus(self:TranslateListName(sp, ty), def)
end

function SAdminCon:GetStatus(class, def_admin)
	if self.Entities[class] == nil then
		return def_admin or self:CheckWL(class)
	else
		return self.Entities[class] ~= self:CheckWL(class)
	end
end

function SAdminCon:SendUpdate(ent, status)
	net.Start("SAdminCon_Update")
	net.WriteString(ent)
	net.WriteBool(status)
	net.SendToServer()
end

function SAdminCon:SendTable(e)
	net.Start("SAdminCon_Data")
	net.WriteUInt(table.Count(e), 16)

	for k, v in pairs(e) do
		net.WriteString(k)
		net.WriteBool(v)
	end

	net.SendToServer()
end

local shield = Material("icon16/shield.png")
function SAdminCon.UpdateContentIcon()
	local ci = vgui.GetControlTable("ContentIcon")
	local si = vgui.GetControlTable("SpawnIcon")

	function ci:GetAdminOnly()
		return SAdminCon:GetStatusPanel(self, self.m_bAdminOnly)
	end

	si.OPaintOver = si.OPaintOver or si.PaintOver
	function si:PaintOver(w, h)
		self:OPaintOver(w, h)
		if self:GetAdminOnly() then
			surface.SetMaterial(shield)
			surface.SetDrawColor(Color(255, 255, 255))
			surface.DrawTexturedRect(w - 14, 6, 11, 11)
		end
	end

	si.OThink = si.OThink or si.Think
	function si:Think()
		if self:GetAdminOnly() and SAdminCon.hide_convar:GetBool() and not self.OldSizeX then
			self.OldSizeX, self.OldSizeY = self:GetSize()
			self:SetSize(0, 0)
			self:SetVisible(false)
		end
		return self:OThink()
	end

	function si:GetAdminOnly()
		return self.playermodel and SAdminCon:GetStatus(self.playermodel)
	end

	function si:DoRightClick()

		local pCanvas = self:GetSelectionCanvas()
		if ( IsValid( pCanvas ) and pCanvas:NumSelectedChildren() > 0 and self:IsSelected() ) then
			return hook.Run( "SpawnlistOpenGenericMenu", pCanvas )
		end

		if self.playermodel and SAdminCon:CanEdit(LocalPlayer()) then
			local menu = DermaMenu()

			menu:AddOption("#spawnmenu.menu.copy", function()
				SetClipboardText(string.gsub(self:GetModelName(), "\\", "/"))
			end):SetIcon("icon16/page_copy.png")

			menu:AddSpacer()

			if not self:GetAdminOnly() then
				menu:AddOption("Restrict to Admins", function()
					SAdminCon:SendUpdate(self.playermodel, true)
				end):SetIcon("icon16/delete.png")
			else
				menu:AddOption("Unrestrict for Everyone", function()
					SAdminCon:SendUpdate(self.playermodel, false)
				end):SetIcon("icon16/add.png")
			end
			menu:Open()
			return
		end

		self:OpenMenu()
	end

	function si:OpenExtraMenu(menu)
		if not SAdminCon:CanEdit(LocalPlayer()) then return end
		menu:AddSpacer()

		if not self:GetAdminOnly() then
			menu:AddOption("Restrict to Admins", function()
				SAdminCon:SendUpdate(self:GetModelName(), true)
			end):SetIcon("icon16/delete.png")
		else
			menu:AddOption("Unrestrict for Everyone", function()
				SAdminCon:SendUpdate(self:GetModelName(), false)
			end):SetIcon("icon16/add.png")
		end
	end


	spawnmenu.s_CreateContentIcon = spawnmenu.s_CreateContentIcon or spawnmenu.CreateContentIcon

	function spawnmenu.CreateContentIcon(type, pnl, data)
		local ic = spawnmenu.s_CreateContentIcon(type, pnl, data)
		if not IsValid(ic) then return ic end

		if types[type] then
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

	SAdminCon.oldModel = SAdminCon.oldModel or spawnmenu.GetContentType("model")

	local oldmodel = SAdminCon.oldModel
	spawnmenu.AddContentType("model", function(container, obj)
		local ic = oldmodel(container, obj)
		function ic:OpenMenu()
			-- Use the containter that we are dragged onto, not the one we were created on
			if (self:GetParent() and self:GetParent().ContentContainer) then
				container = self:GetParent().ContentContainer
			end

			local menu = DermaMenu()

			menu:AddOption("#spawnmenu.menu.copy", function()
				SetClipboardText(string.gsub(self:GetModelName(), "\\", "/"))
			end):SetIcon("icon16/page_copy.png")

			menu:AddOption("#spawnmenu.menu.spawn_with_toolgun", function()
				RunConsoleCommand("gmod_tool", "creator")
				RunConsoleCommand("creator_type", "4")
				RunConsoleCommand("creator_name", self:GetModelName())
			end):SetIcon("icon16/brick_add.png")

			local submenu, submenu_opt = menu:AddSubMenu("#spawnmenu.menu.rerender", function()
				if (IsValid(self)) then
					self:RebuildSpawnIcon()
				end
			end)

			submenu_opt:SetIcon("icon16/picture_save.png")

			submenu:AddOption("#spawnmenu.menu.rerender_this", function()
				if (IsValid(self)) then
					self:RebuildSpawnIcon()
				end
			end):SetIcon("icon16/picture.png")

			submenu:AddOption("#spawnmenu.menu.rerender_all", function()
				if (IsValid(container)) then
					container:RebuildAll()
				end
			end):SetIcon("icon16/pictures.png")

			menu:AddOption("#spawnmenu.menu.edit_icon", function()
				if (not IsValid(self)) then return end
				local editor = vgui.Create("IconEditor")
				editor:SetIcon(self)
				editor:Refresh()
				editor:MakePopup()
				editor:Center()
			end):SetIcon("icon16/pencil.png")

			-- Do not allow removal/size changes from read only panels
			if (IsValid(self:GetParent()) and self:GetParent().GetReadOnly and self:GetParent():GetReadOnly()) then
				menu:Open()
				self:OpenExtraMenu(menu)

				return
			end

			self:InternalAddResizeMenu(menu, function(w, h)
				if (not IsValid(self)) then return end
				self:SetSize(w, h)
				self:InvalidateLayout(true)
				container:OnModified()
				container:Layout()
				self:SetModel(self:GetModelName(), obj.skin or 0, obj.body)
			end)

			menu:AddSpacer()

			menu:AddOption("#spawnmenu.menu.delete", function()
				if (not IsValid(self)) then return end
				self:Remove()
				hook.Run("SpawnlistContentChanged")
			end):SetIcon("icon16/bin_closed.png")

			self:OpenExtraMenu(menu)

			menu:Open()
		end

		function ic:OpenExtraMenu(menu)
			if not SAdminCon:CanEdit(LocalPlayer()) then return end
			menu:AddSpacer()

			if not self:GetAdminOnly() then
				menu:AddOption("Restrict to Admins", function()
					SAdminCon:SendUpdate(self:GetModelName(), true)
				end):SetIcon("icon16/delete.png")
			else
				menu:AddOption("Unrestrict for Everyone", function()
					SAdminCon:SendUpdate(self:GetModelName(), false)
				end):SetIcon("icon16/add.png")
			end
		end

		function ic:GetAdminOnly()
			return SAdminCon:GetStatus(self:GetModelName())
		end

		ic.OPaintOver = ic.OPaintOver or ic.PaintOver
		function ic:PaintOver(w, h)
			self:OPaintOver(w, h)
			if SAdminCon:GetStatus(self:GetModelName()) then
				surface.SetMaterial(shield)
				surface.SetDrawColor(Color(255, 255, 255))
				surface.DrawTexturedRect(w - 14, 6, 11, 11)
			end
		end

		ic.OThink = ic.OThink or ic.Think
		function ic:Think()
			if self:GetAdminOnly() and SAdminCon.hide_convar:GetBool() and not self.OldSizeX then
				self.OldSizeX, self.OldSizeY = self:GetSize()
				self:SetSize(0, 0)
				self:SetVisible(false)
			end
			return self:OThink()
		end
		return ic
	end)

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

			option.OPaint = option.OPaint or option.Paint
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

net.Receive("SAdminCon_Data", function(_, ply)
	local clear = net.ReadBool()
	local parts = net.ReadUInt(6)
	local cpart = net.ReadUInt(6)
	local len = net.ReadUInt(16)

	if clear and cpart == 1 then
		SAdminCon.Entities = {}
	end

	print("[SAC] Downloading Data Parts " .. cpart .. "/" .. parts)

	for i = 1, len do
		local k, v = net.ReadString(), net.ReadUInt(3)
		if v ~= 2 then
			SAdminCon.Entities[k] = v == 1 and true or false
		else
			SAdminCon.Entities[k] = nil
		end
	end
end)

net.Receive("SAdminCon_Update", function(_, ply)
	local k, v = net.ReadString(), net.ReadUInt(3)
	if v ~= 2 then
		SAdminCon.Entities[k] = v == 1 and true or false
	else
		SAdminCon.Entities[k] = nil
	end

	if SAdminCon.hide_convar:GetBool() and not SAdminCon:IsAdmin(LocalPlayer()) then
		timer.Create("UpdateSpawnmenu", 15, 1, function()
			RunConsoleCommand("spawnmenu_reload")
		end)
	end
end)

hook.Add("PreGamemodeLoaded", "SAdminCon_UpdateIcon", SAdminCon.UpdateContentIcon)
hook.Add("SpawnMenuCreated", "SAdminCon_UpdateIcon", SAdminCon.UpdateContentIcon)

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
				local name = SAdminCon:TranslateListName(v.spawnname, v.type)
				if SAdminCon:GetStatus(name) then continue end
				tbl[name] = true
			end

			SAdminCon:SendTable(tbl)
		end):SetIcon("icon16/delete.png")

		menu:AddOption("Unrestrict Category", function()
			local tbl = {}

			for k, v in pairs(pnl:ContentsToTable()) do
				local name = SAdminCon:TranslateListName(v.spawnname, v.type)
				if not SAdminCon:GetStatus(name) then continue end
				tbl[name] = false
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


-- Toolmenu Tab
hook.Add("AddToolMenuCategories", "SAC_ToolSettings", function()
	spawnmenu.AddToolCategory("Utilities", "SAC", "#SimpleAdminOnly")
end)

hook.Add("PopulateToolMenu", "SAC_ToolSettings", function()
	spawnmenu.AddToolMenuOption("Utilities", "SAC", "SimpleAdminOnly", "#SAC Settings", "", "", function(panel)
		panel:Help("This menu is WIP and not fully working yet :("):SetFont("ScoreboardDefault")
		-- Presets
		-- local presets = vgui.Create("Panel", panel)
		-- presets.DropDown = vgui.Create("DComboBox", presets)
		-- presets.DropDown.OnSelect = function(dropdown, index, value, data) presets:OnSelect(index, value, data) end
		-- presets.DropDown:SetText("Presets")
		-- presets.DropDown:Dock(FILL)

		-- presets.CopyButton = vgui.Create("DImageButton", presets)
		-- presets.CopyButton.DoClick = function() presets:OpenPresetEditor() end
		-- presets.CopyButton:Dock(RIGHT)
		-- presets.CopyButton:SetImage("icon16/disk_multiple.png")
		-- presets.CopyButton:SetStretchToFit(false)
		-- presets.CopyButton:SetSize(20, 20)
		-- presets.CopyButton:DockMargin(0, 0, 0, 0)

		-- presets.AddButton = vgui.Create("DImageButton", presets)
		-- presets.AddButton.DoClick = function(self)
		-- 	if not IsValid(self) then return end

		-- 	self:QuickSavePreset()
		-- end
		-- presets.AddButton:Dock(RIGHT)
		-- presets.AddButton:SetTooltip("#preset.add")
		-- presets.AddButton:SetImage("icon16/add.png")
		-- presets.AddButton:SetStretchToFit(false)
		-- presets.AddButton:SetSize(20, 20)
		-- presets.AddButton:DockMargin(2, 0, 0, 0)

		-- presets.DelButton = vgui.Create("DImageButton", presets)
		-- presets.DelButton.DoClick = function() presets:OpenPresetEditor() end
		-- presets.DelButton:Dock(RIGHT)
		-- presets.DelButton:SetImage("icon16/delete.png")
		-- presets.DelButton:SetStretchToFit(false)
		-- presets.DelButton:SetSize(20, 20)
		-- presets.DelButton:DockMargin(0, 0, 0, 0)

		-- function presets:OnSelect(ind, val, data)

		-- end

		-- presets:SetTall(20)
		-- panel:AddItem(presets)


		-- for k, v in pairs(file.Find("sac/*.json", "DATA")) do
		-- 	presets.DropDown:AddChoice(v:StripExtension():gsub("^%l", string.upper), v, v == "default.json")
		-- end

		local cat_table = table.Copy(SAdminCon.Categories)
		local cats = {}
		table.insert(cat_table, "other")

		for k, v in pairs(cat_table) do
			local name = SAdminCon.HumanCat[k]
			panel:Help(name):SetFont("ScoreboardDefault")
			if v ~= "other" then
				panel:CheckBox("Whitelist for " .. name, "sac_wl_" .. v)
			end

			local items = vgui.Create("DListView")
			items:AddColumn("Right click to remove")
			items:AddColumn("Black/Whitelisted"):ResizeColumn(10)
			items:SetTall(20)
			items:SetMultiSelect(false)
			function items:OnRowRightClick(number, d)

			end
			cats[v] = items
			panel:AddItem(items)
		end

		for k, v in pairs(SAdminCon.Entities) do
			local cat = SAdminCon:GetCategory(k) or "other"
			local ct = cats[cat]
			ct:AddLine(k, tostring(v))
			ct:SetTall(math.min(ct:GetTall() + 18, 130))
		end

	end)
end)