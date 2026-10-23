--!nocheck
--[[
    thdreams's menu  (Universal)
    Players, movement, visuals, troll tools and server info built on the
    BlekLib UI library.

    Usage:
      * Execute this script in your executor (no Studio needed).
      * Press RightShift to open or close the menu.
      * Players tab: click a row to select someone, then use the action buttons.
      * Spectating: one button toggles it on and off. While it is on your
      character is frozen in place; move the mouse (or drag, or use the arrow
      keys) to orbit the target, wheel to zoom.
      * Troll tab: follow / orbit / fling the selected player, spin, ragdoll,
        sit, stand and dance with your own character.

    Re-running the script unloads the previous menu and restores every
    property it changed (speed, jump, noclip, fly, camera, lighting, fog, FOV).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

-- Clean up a previous run ---------------------------------------------------

local env = (getgenv and getgenv()) or _G
if env.TokyoMultitoolCleanup then
    pcall(env.TokyoMultitoolCleanup)
end
if env.PlayerListCleanup then
    pcall(env.PlayerListCleanup)
end
if env.PlayerListConnections then
    for _, connection in ipairs(env.PlayerListConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    env.PlayerListConnections = nil
end
pcall(function()
    ContextActionService:UnbindAction("FreezeMovement")
end)

local active = true
local connections = {}
local function track(connection)
    table.insert(connections, connection)
    return connection
end

-- BlekLib UI -----------------------------------------------------------------
-- The interface is built on BlekLib (OptioniaI/bleklib). BlekLib only ships
-- buttons, toggles, sliders and textboxes, so the player list, the live labels
-- and the search box are small custom controls drawn inside its tab holders
-- with the same look. The old Tokyo backdrop that swallowed mouse input is not
-- part of this window at all, so the camera keeps working.

local BLEK_URL = "https://raw.githubusercontent.com/OptioniaI/bleklib/main/library.lua"

local blekDownloaded, blekSource = pcall(function()
    return game:HttpGet(BLEK_URL)
end)
if not blekDownloaded or type(blekSource) ~= "string" or #blekSource < 1000 then
    error("BlekLib: failed to download " .. BLEK_URL, 0)
end

-- BlekLib still uses the legacy lowercase signal aliases (:connect / :wait),
-- which not every client keeps around. Normalise them while loading.
blekSource = string.gsub(blekSource, ":%s*connect%(", ":Connect(")
blekSource = string.gsub(blekSource, ":%s*wait%(", ":Wait(")

local blekChunk, blekCompileError = loadstring(blekSource)
if type(blekChunk) ~= "function" then
    error("BlekLib failed to compile: " .. tostring(blekCompileError), 0)
end

local BlekLib = blekChunk()
if type(BlekLib) ~= "table" or type(BlekLib.Create) ~= "function" then
    error("BlekLib did not return the library table.", 0)
end

local blekWin = BlekLib:Create({
    Name = "thdreams's menu",
    StartupSound = {
        Toggle = false,
        SoundID = "rbxassetid://6958727243",
        TimePosition = 1,
    },
})

local coreGui
pcall(function()
    coreGui = game:GetService("CoreGui")
end)
if not coreGui then
    pcall(function()
        coreGui = game.CoreGui
    end)
end

local blekScreen
if coreGui then
    pcall(function()
        blekScreen = coreGui:FindFirstChild("dark_UI")
    end)
end
if not blekScreen then
    pcall(function()
        blekScreen = game.CoreGui:FindFirstChild("dark_UI")
    end)
end

local blekMain = blekScreen and blekScreen:FindFirstChild("main")
if blekScreen then
    blekScreen.Enabled = true
end

-- The library title label is 83 px wide, too narrow for the menu name.
if blekMain then
    local title = blekMain:FindFirstChild("title")
    if title then
        pcall(function()
            title.Text = "thdreams's menu"
            title.Size = UDim2.new(0, 300, 0, 28)
            title.Position = UDim2.new(0, 16, 0, 14)
            title.TextXAlignment = Enum.TextXAlignment.Left
        end)
    end
end

-- Size ---------------------------------------------------------------------
-- BlekLib lays the window and its tabs out in fixed pixel offsets, so stretching
-- main.Size alone would only add empty space. A UIScale on the window scales the
-- layout, the labels and the rows drawn inside it together.
local MENU_SCALE = 1.2

local function applyMenuScale()
    if not blekMain then
        return
    end

    pcall(function()
        local scale = blekMain:FindFirstChild("thdreamsScale")
        if not scale then
            scale = Instance.new("UIScale")
            scale.Name = "thdreamsScale"
            scale.Parent = blekMain
        end
        scale.Scale = MENU_SCALE
    end)

    -- The library centres the window with AnchorPoint (0.5, 0.5) and its drag
    -- handler compensates with the unscaled offset size, so with a scale the
    -- frame would jump away from the cursor on the first drag. Anchoring the
    -- top-left corner and centring with offsets keeps that maths exact.
    pcall(function()
        local size = blekMain.Size
        local width = (size.X.Offset or 0) * MENU_SCALE
        local height = (size.Y.Offset or 0) * MENU_SCALE
        blekMain.AnchorPoint = Vector2.new(0, 0)
        blekMain.Position = UDim2.new(0.5, -math.floor(width / 2), 0.5, -math.floor(height / 2))
    end)

    -- No drop shadow under the window. The object stays alive but invisible:
    -- BlekLib's drag handler tweens it on every frame, and destroying it would
    -- leave that tween pointing at a destroyed instance.
    if not blekScreen then
        return
    end

    pcall(function()
        local shadow = blekScreen:FindFirstChild("shadow")
        if not shadow then
            return
        end
        shadow.Visible = false
        local scale = shadow:FindFirstChild("thdreamsScale")
        if scale then
            scale:Destroy()
        end
    end)
end

applyMenuScale()

local function pointerLocation()
    local ok, location = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if ok then
        return location
    end
    return nil
end

-- Layout --------------------------------------------------------------------
-- BlekLib sizes the tab strip and every tab container with fixed offsets, so a
-- resized window would keep a 454x183 box in the corner. These margins keep the
-- content filling the window at any size.
local MENU_MIN_WIDTH, MENU_MIN_HEIGHT = 380, 240
local menuWidth, menuHeight = 488, 299

local function menuLimits()
    local maxWidth, maxHeight = 980, 680
    pcall(function()
        local camera = workspace.CurrentCamera
        if camera and camera.ViewportSize then
            maxWidth = math.max(MENU_MIN_WIDTH, camera.ViewportSize.X / MENU_SCALE - 24)
            maxHeight = math.max(MENU_MIN_HEIGHT, camera.ViewportSize.Y / MENU_SCALE - 24)
        end
    end)
    return maxWidth, maxHeight
end

local function applyMenuLayout()
    if not blekMain then
        return
    end

    pcall(function()
        blekMain.Size = UDim2.fromOffset(menuWidth, menuHeight)

        local tabs = blekMain:FindFirstChild("tabContainer")
        if tabs then
            tabs.Position = UDim2.fromOffset(17, 56)
            tabs.Size = UDim2.fromOffset(menuWidth - 34, 30)
        end

        for _, child in ipairs(blekMain:GetChildren()) do
            if child.Name == "container" then
                child.Position = UDim2.fromOffset(17, 92)
                child.Size = UDim2.fromOffset(menuWidth - 34, menuHeight - 118)
                local holder = child:FindFirstChild("holder")
                if holder then
                    holder.Position = UDim2.fromOffset(1, 1)
                    holder.Size = UDim2.new(1, -2, 1, -2)
                end
            end
        end
    end)
end

applyMenuLayout()

-- Window chrome -------------------------------------------------------------
-- Grip, minimise and close live next to the window, not inside it: clicking
-- anything inside main also starts BlekLib's drag handler (it listens on
-- main.InputBegan), so chrome in there would drag the window while used.
local resizeGrip
local minimizeChrome
local closeChrome
-- Assigned below, once the launcher exists; the chrome button only calls it.
local minimizeMenu

local CHROME_BG = Color3.fromRGB(52, 52, 52)
local CHROME_HOVER = Color3.fromRGB(70, 70, 70)
local CHROME_ICON = Color3.fromRGB(176, 176, 176)

-- Icons are drawn from thin frames instead of font glyphs, so they look the
-- same in every executor and font fallback.
local function chromeIcon(parent, width, height, x, y, rotation)
    local line = Instance.new("Frame")
    line.Size = UDim2.fromOffset(width, height)
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.Position = UDim2.fromOffset(x, y)
    line.Rotation = rotation or 0
    line.BackgroundColor3 = CHROME_ICON
    line.BorderSizePixel = 0
    line.ZIndex = 12
    line.Parent = parent
    return line
end

local function makeChromeButton(name)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = UDim2.fromOffset(18, 18)
    button.BackgroundColor3 = CHROME_BG
    button.BackgroundTransparency = 0.25
    button.AutoButtonColor = false
    button.Text = ""
    button.ZIndex = 11
    button.Parent = blekScreen

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = button

    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = CHROME_HOVER
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = CHROME_BG
    end)

    return button
end

local function placeWindowChrome()
    if not blekMain then
        return
    end
    pcall(function()
        local position = blekMain.AbsolutePosition
        local size = blekMain.AbsoluteSize
        if not position or not size then
            return
        end
        if resizeGrip then
            resizeGrip.Position = UDim2.fromOffset(position.X + size.X - 20, position.Y + size.Y - 20)
        end
        if minimizeChrome then
            minimizeChrome.Position = UDim2.fromOffset(position.X + size.X - 48, position.Y + 8)
        end
        if closeChrome then
            closeChrome.Position = UDim2.fromOffset(position.X + size.X - 26, position.Y + 8)
        end
    end)
end

local function createWindowChrome()
    if not blekScreen or not blekMain or resizeGrip then
        return
    end

    pcall(function()
        local grip = makeChromeButton("thdreamsResize")
        -- Arrow pointing into the corner it drags.
        chromeIcon(grip, 11, 2, 9, 9, 45)
        chromeIcon(grip, 6, 2, 10, 13, 0)
        chromeIcon(grip, 6, 2, 13, 10, 90)
        resizeGrip = grip

        local minimize = makeChromeButton("thdreamsMinimize")
        chromeIcon(minimize, 9, 2, 9, 9, 0)
        minimize.MouseButton1Click:Connect(function()
            minimizeMenu()
        end)
        minimizeChrome = minimize

        local close = makeChromeButton("thdreamsClose")
        chromeIcon(close, 9, 2, 9, 9, 45)
        chromeIcon(close, 9, 2, 9, 9, -45)
        close.MouseButton1Click:Connect(function()
            -- env is filled at the end of the script; resolve it when clicked.
            local unload = env.TokyoMultitoolCleanup
            if unload then
                pcall(unload)
            end
        end)
        closeChrome = close

        placeWindowChrome()
        track(RunService.RenderStepped:Connect(placeWindowChrome))

        local resizing = false
        local startWidth, startHeight = 0, 0
        local startX, startY = 0, 0

        grip.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local location = pointerLocation()
            if not location then
                return
            end
            resizing = true
            startWidth, startHeight = menuWidth, menuHeight
            startX, startY = location.X, location.Y
        end)

        track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                resizing = false
            end
        end))

        track(UserInputService.InputChanged:Connect(function(input)
            if not resizing or input.UserInputType ~= Enum.UserInputType.MouseMovement then
                return
            end
            local location = pointerLocation()
            if not location then
                return
            end
            local maxWidth, maxHeight = menuLimits()
            -- The window is drawn through a UIScale, so one rendered pixel is
            -- 1 / MENU_SCALE of an offset.
            menuWidth = math.floor(math.clamp(startWidth + (location.X - startX) / MENU_SCALE, MENU_MIN_WIDTH, maxWidth))
            menuHeight = math.floor(math.clamp(startHeight + (location.Y - startY) / MENU_SCALE, MENU_MIN_HEIGHT, maxHeight))
            applyMenuLayout()
            placeWindowChrome()
        end))
    end)
end

createWindowChrome()

local menuOpen = true
local miniGui
local miniButton

local function setMenuOpen(open)
    menuOpen = open == true
    if blekScreen then
        pcall(function()
            blekScreen.Enabled = menuOpen
        end)
    end
    if miniGui then
        pcall(function()
            miniGui.Enabled = not menuOpen
        end)
    end
end

-- Minimised launcher ---------------------------------------------------------
-- Minimising hides the window and leaves this small button behind: drag it
-- anywhere on screen, click it to bring the menu back.
local miniDragging = false
local miniMoved = false
local miniStart = { x = 0, y = 0, buttonX = 0, buttonY = 0 }

local function ensureMiniButton()
    if miniButton and miniButton.Parent then
        return miniButton
    end
    if not coreGui then
        return nil
    end

    miniGui = Instance.new("ScreenGui")
    miniGui.Name = "thdreams_mini"
    miniGui.IgnoreGuiInset = true
    miniGui.ResetOnSpawn = false
    miniGui.Parent = coreGui

    local button = Instance.new("TextButton")
    button.Name = "mini"
    button.Size = UDim2.fromOffset(132, 30)
    button.Position = UDim2.fromOffset(24, 120)
    button.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
    button.AutoButtonColor = false
    button.Text = "thdreams's menu"
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 13
    button.TextColor3 = Color3.fromRGB(196, 196, 196)
    button.ZIndex = 2
    button.Parent = miniGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(76, 76, 76)
    stroke.Thickness = 1
    stroke.Parent = button

    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
    end)

    button.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        local location = pointerLocation()
        if not location then
            return
        end
        local position = button.AbsolutePosition
        miniDragging = true
        miniMoved = false
        miniStart.x, miniStart.y = location.X, location.Y
        miniStart.buttonX, miniStart.buttonY = position.X, position.Y
    end)

    -- A click reopens the window; a drag only moves the launcher.
    button.MouseButton1Click:Connect(function()
        miniDragging = false
        if not miniMoved then
            setMenuOpen(true)
        end
    end)

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            miniDragging = false
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not miniDragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        local location = pointerLocation()
        if not location then
            return
        end
        local dx = location.X - miniStart.x
        local dy = location.Y - miniStart.y
        if math.abs(dx) > 4 or math.abs(dy) > 4 then
            miniMoved = true
        end
        if miniMoved then
            button.Position = UDim2.fromOffset(
                math.max(0, miniStart.buttonX + dx),
                math.max(0, miniStart.buttonY + dy)
            )
        end
    end))

    miniButton = button
    return button
end

minimizeMenu = function()
    -- Without a launcher there would be no way back to the menu.
    if ensureMiniButton() then
        setMenuOpen(false)
    end
end

-- The wheel belongs to the menu while the pointer is over it: it scrolls the
-- list and must not also zoom the spectate camera.
local function pointerOverMenu()
    if not menuOpen or not blekMain or not blekMain.Parent then
        return false
    end

    local ok, location = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if not ok or not location then
        return false
    end

    local position, size = blekMain.AbsolutePosition, blekMain.AbsoluteSize
    if not position or not size then
        return false
    end

    -- GetMouseLocation is in screen space, top bar included; a normal ScreenGui
    -- child has its origin below that bar.
    local insetY = 0
    if not (blekScreen and blekScreen.IgnoreGuiInset) then
        pcall(function()
            local guiService = game:GetService("GuiService")
            insetY = guiService:GetGuiInset().Y
        end)
    end

    local x, y = location.X, location.Y - insetY
    return x >= position.X
        and x <= position.X + size.X
        and y >= position.Y
        and y <= position.Y + size.Y
end

-- Toasts -------------------------------------------------------------------

local toastGui
local toastHolder

local function ensureToasts()
    if toastGui and toastGui.Parent then
        return
    end
    if not coreGui then
        return
    end

    toastGui = Instance.new("ScreenGui")
    toastGui.Name = "thdreams_toasts"
    toastGui.IgnoreGuiInset = true
    toastGui.ResetOnSpawn = false
    toastGui.DisplayOrder = 1000

    toastHolder = Instance.new("Frame")
    toastHolder.BackgroundTransparency = 1
    toastHolder.Size = UDim2.new(0, 300, 1, 0)
    toastHolder.Position = UDim2.new(1, -312, 0, 76)
    toastHolder.Parent = toastGui

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.Parent = toastHolder

    toastGui.Parent = coreGui
end

local function showToast(message)
    ensureToasts()
    if not toastHolder then
        return
    end

    local toast = Instance.new("TextLabel")
    toast.Size = UDim2.new(1, 0, 0, 32)
    toast.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    toast.BackgroundTransparency = 0.05
    toast.TextColor3 = Color3.fromRGB(228, 228, 228)
    toast.TextSize = 13
    toast.Font = Enum.Font.Gotham
    toast.TextWrapped = true
    toast.Text = tostring(message)
    toast.Parent = toastHolder

    local toastCorner = Instance.new("UICorner")
    toastCorner.CornerRadius = UDim.new(0, 6)
    toastCorner.Parent = toast

    pcall(task.delay, 3, function()
        pcall(function()
            toast:Destroy()
        end)
    end)
end

-- Controls -----------------------------------------------------------------

-- Rows fill the tab holder instead of a fixed 441 px, so they follow a
-- resized window (the holder keeps 5 px of left padding and a 2 px scroll bar).
local ROW_INSET = 11
local CONTROL_BG = Color3.fromRGB(38, 38, 38)
local CONTROL_HOVER = Color3.fromRGB(45, 45, 45)
local TEXT_COLOR = Color3.fromRGB(196, 196, 196)
local MUTED_COLOR = Color3.fromRGB(152, 152, 152)
local HEADER_COLOR = Color3.fromRGB(168, 168, 168)
local TOGGLE_OFF = Color3.fromRGB(45, 45, 45)
local TOGGLE_ON = Color3.fromRGB(23, 143, 75)
local STROKE_OFF = Color3.fromRGB(76, 76, 76)
local STROKE_ON = Color3.fromRGB(32, 202, 106)

local library = { options = {} }
local registry = {}
env.ThdreamsControls = registry
env.ThdreamsSections = {}
env.ThdreamsTabs = {}

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 6)
    corner.Parent = parent
    return corner
end

local function makeRow()
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -ROW_INSET, 0, 32)
    row.BackgroundColor3 = CONTROL_BG
    row.Text = ""
    row.AutoButtonColor = false
    makeCorner(row, 6)

    row.MouseEnter:Connect(function()
        row.BackgroundColor3 = CONTROL_HOVER
    end)
    row.MouseLeave:Connect(function()
        row.BackgroundColor3 = CONTROL_BG
    end)

    return row
end

local function makeRowLabel(row, text)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -46, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Font = Enum.Font.Gotham
    label.Text = tostring(text or "")
    label.TextColor3 = TEXT_COLOR
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    return label
end

local function buildSection(tab, name)
    local header = Instance.new("TextLabel")
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, -ROW_INSET, 0, 20)
    header.Font = Enum.Font.GothamSemibold
    header.Text = string.upper(name)
    header.TextColor3 = HEADER_COLOR
    header.TextSize = 12
    header.TextXAlignment = Enum.TextXAlignment.Left
    tab.addControl(header)

    local section = { text = name, options = {} }

    local function register(class, label, control)
        control.class = class
        control.sectionName = name
        table.insert(section.options, control)
        registry[name .. "|" .. class .. "|" .. tostring(label)] = control
        return control
    end

    function section:UpdateOptions()
        for _, option in ipairs(self.options) do
            if option.instance then
                option.instance.Visible = option.enabled ~= false
            end
        end
    end

    function section:AddText(data)
        data = data or {}
        local row = Instance.new("Frame")
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, -ROW_INSET, 0, 24)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, -12, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextColor3 = MUTED_COLOR
        label.TextWrapped = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = tostring(data.text or "")
        label.Parent = row

        tab.addControl(row)

        local text = {
            text = tostring(data.text or ""),
            instance = row,
            objects = { text = label },
        }
        function text:SetText(value)
            self.text = tostring(value or "")
            label.Text = self.text
        end

        return register("text", data.text or "", text)
    end

    function section:AddToggle(data)
        data = data or {}
        local row = makeRow()
        local label = makeRowLabel(row, data.text)

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.new(0, 18, 0, 18)
        indicator.Position = UDim2.new(1, -28, 0.5, -9)
        indicator.BackgroundColor3 = TOGGLE_OFF
        makeCorner(indicator, 3)
        indicator.Parent = row

        local stroke = Instance.new("UIStroke")
        stroke.Color = STROKE_OFF
        stroke.Parent = indicator

        tab.addControl(row)

        local toggle = {
            text = data.text or "Toggle",
            flag = data.flag,
            state = data.state == true,
            callback = data.callback or function() end,
            enabled = true,
            instance = row,
            objects = { indicator = indicator, text = label, holder = row },
        }

        function toggle:SetState(value, nocallback)
            self.state = value == true
            indicator.BackgroundColor3 = self.state and TOGGLE_ON or TOGGLE_OFF
            stroke.Color = self.state and STROKE_ON or STROKE_OFF
            if not nocallback then
                self.callback(self.state)
            end
        end

        row.MouseButton1Click:Connect(function()
            if toggle.enabled == false then
                return
            end
            toggle:SetState(not toggle.state)
        end)

        if data.flag then
            library.options[data.flag] = toggle
        end

        register("toggle", data.text or "Toggle", toggle)
        toggle:SetState(toggle.state, true)
        return toggle
    end

    function section:AddButton(data)
        data = data or {}
        local row = makeRow()
        local label = makeRowLabel(row, data.text)
        local subHolder

        tab.addControl(row)

        local button = {
            text = data.text or "Button",
            callback = data.callback or function() end,
            enabled = true,
            instance = row,
            subbuttons = {},
            objects = { text = label },
        }

        function button:SetText(value)
            self.text = tostring(value or "")
            label.Text = self.text
        end

        function button:AddButton(subData)
            subData = subData or {}
            if not subHolder then
                subHolder = Instance.new("Frame")
                subHolder.BackgroundTransparency = 1
                subHolder.Size = UDim2.new(1, -8, 1, -4)
                subHolder.Position = UDim2.new(0, 4, 0, 2)
                subHolder.Parent = row
                label.Visible = false
            end

            local subRow = Instance.new("TextButton")
            subRow.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
            subRow.Text = ""
            subRow.AutoButtonColor = false
            makeCorner(subRow, 5)

            local subLabel = Instance.new("TextLabel")
            subLabel.BackgroundTransparency = 1
            subLabel.Size = UDim2.new(1, -8, 1, 0)
            subLabel.Position = UDim2.new(0, 4, 0, 0)
            subLabel.Font = Enum.Font.Gotham
            subLabel.Text = tostring(subData.text or "Button")
            subLabel.TextColor3 = TEXT_COLOR
            subLabel.TextSize = 12
            subLabel.TextXAlignment = Enum.TextXAlignment.Center
            subLabel.Parent = subRow

            subRow.Parent = subHolder

            local subButton = {
                text = subData.text or "Button",
                callback = subData.callback or function() end,
                enabled = true,
                instance = subRow,
                objects = { text = subLabel },
            }
            function subButton:SetText(value)
                self.text = tostring(value or "")
                subLabel.Text = self.text
            end

            subRow.MouseButton1Click:Connect(function()
                if subButton.enabled ~= false then
                    subButton.callback()
                end
            end)

            table.insert(self.subbuttons, subButton)
            local count = #self.subbuttons
            for index, entry in ipairs(self.subbuttons) do
                entry.instance.Size = UDim2.new(1 / count, -2, 1, 0)
                entry.instance.Position = UDim2.new((index - 1) / count, 1, 0, 0)
            end

            return subButton
        end

        row.MouseButton1Click:Connect(function()
            if button.enabled ~= false and #button.subbuttons == 0 then
                button.callback()
            end
        end)

        register("button", data.text or "Button", button)
        return button
    end

    function section:AddSlider(data)
        data = data or {}
        local row = makeRow()
        makeRowLabel(row, data.text)

        local min = tonumber(data.min) or 0
        local max = tonumber(data.max) or 100
        local step = tonumber(data.increment) or 1
        local value = tonumber(data.value) or min

        local valueLabel = Instance.new("TextLabel")
        valueLabel.BackgroundTransparency = 1
        valueLabel.Size = UDim2.new(0, 42, 1, 0)
        valueLabel.Position = UDim2.new(1, -176, 0, 0)
        valueLabel.Font = Enum.Font.Gotham
        valueLabel.TextColor3 = TEXT_COLOR
        valueLabel.TextSize = 12
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Text = tostring(value)
        valueLabel.Parent = row

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 118, 0, 8)
        track.Position = UDim2.new(1, -128, 0.5, -4)
        track.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
        makeCorner(track, 4)
        track.Parent = row

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(76, 76, 76)
        makeCorner(fill, 4)
        fill.Parent = track

        tab.addControl(row)

        local slider = {
            text = data.text or "Slider",
            flag = data.flag,
            value = value,
            min = min,
            max = max,
            increment = step,
            callback = data.callback or function() end,
            enabled = true,
            instance = row,
            objects = { text = valueLabel, track = track, fill = fill },
        }

        local function apply(raw, nocallback)
            local clamped = math.clamp(tonumber(raw) or min, min, max)
            if step > 0 then
                clamped = math.floor(clamped / step + 0.5) * step
            end
            clamped = math.clamp(clamped, min, max)
            if step >= 1 then
                clamped = math.floor(clamped + 0.5)
            end

            slider.value = clamped
            valueLabel.Text = tostring(clamped)
            local fraction = max > min and (clamped - min) / (max - min) or 0
            fill.Size = UDim2.new(fraction, 0, 1, 0)

            if not nocallback then
                slider.callback(clamped)
            end
        end

        function slider:SetValue(newValue, nocallback)
            apply(newValue, nocallback)
        end

        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            local function update()
                local mouse = UserInputService:GetMouseLocation()
                local fraction = math.clamp(
                    (mouse.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1),
                    0,
                    1
                )
                apply(min + (max - min) * fraction)
            end

            update()
            task.spawn(function()
                while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    update()
                    RunService.RenderStepped:Wait()
                end
            end)
        end)

        if data.flag then
            library.options[data.flag] = slider
        end

        register("slider", data.text or "Slider", slider)
        apply(value, true)
        return slider
    end

    function section:AddBox(data)
        data = data or {}
        local row = makeRow()
        makeRowLabel(row, data.text)

        local input = Instance.new("TextBox")
        input.Size = UDim2.new(0, 150, 0, 20)
        input.Position = UDim2.new(1, -160, 0.5, -10)
        input.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
        input.TextColor3 = TEXT_COLOR
        input.TextSize = 12
        input.Font = Enum.Font.SourceSans
        input.ClearTextOnFocus = false
        input.Text = ""
        makeCorner(input, 5)
        input.Parent = row

        tab.addControl(row)

        local box = {
            text = data.text or "Textbox",
            flag = data.flag,
            input = "",
            focused = false,
            callback = data.callback or function() end,
            enabled = true,
            instance = row,
            objects = { inputText = input },
        }

        input:GetPropertyChangedSignal("Text"):Connect(function()
            local value = input.Text
            box.input = value
            box.callback(value)
        end)

        input.Focused:Connect(function()
            box.focused = true
        end)

        input.FocusLost:Connect(function()
            box.focused = false
            box.input = input.Text
            box.callback(input.Text)
        end)

        function box:SetInput(value, nocallback)
            value = tostring(value or "")
            self.input = value
            input.Text = value
            if not nocallback then
                self.callback(value)
            end
        end

        function box:CaptureFocus(clear)
            self.focused = true
            if clear then
                input.Text = ""
            end
            pcall(function()
                input:CaptureFocus()
            end)
        end

        function box:ReleaseFocus()
            self.focused = false
            pcall(function()
                input:ReleaseFocus()
            end)
        end

        if data.flag then
            library.options[data.flag] = box
        end

        register("box", data.text or "Textbox", box)
        return box
    end

    return section
end

local blekContainers = {}
local blekTabCount = 0

local function makeTab(name)
    blekWin:Tab(name)

    local container
    if blekMain then
        for _, child in ipairs(blekMain:GetChildren()) do
            if child.Name == "container" and not blekContainers[child] then
                container = child
            end
        end
    end
    if container then
        blekContainers[container] = true
        blekTabCount = blekTabCount + 1
        -- BlekLib leaves every container hidden until a tab is clicked.
        if blekTabCount == 1 then
            container.Visible = true
        end
    end

    local holder = container and container:FindFirstChild("holder")
    if not holder then
        error("BlekLib changed: the tab content holder was not found.", 0)
    end

    pcall(function()
        holder.ClipsDescendants = true
        holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
        holder.CanvasSize = UDim2.new(0, 0, 0, 0)
        holder.ScrollingDirection = Enum.ScrollingDirection.Y
    end)

    -- New containers start at BlekLib's fixed size; fit them to the window.
    applyMenuLayout()

    local tab = { text = name, sections = {}, holder = holder }
    table.insert(env.ThdreamsTabs, tab)
    local order = 0

    local function addControl(instance)
        order = order + 1
        instance.LayoutOrder = order
        instance.Parent = holder
        return instance
    end

    tab.addControl = addControl

    function tab:AddSection(sectionName)
        local section = buildSection(self, sectionName)
        table.insert(self.sections, section)
        env.ThdreamsSections[sectionName] = section
        return section
    end

    function tab:UpdateSections()
        -- Sections stack in one scrolling column; nothing to reposition.
    end

    return tab
end

local window = {}

function window:AddTab(name)
    return makeTab(name)
end

function library:SendNotification(message)
    showToast(message)
end

function library:Unload()
    pcall(function()
        blekWin:Exit()
    end)
end

local playersTab = window:AddTab("Players")
local movementTab = window:AddTab("Movement")
local visualsTab = window:AddTab("Visuals")
local trollTab = window:AddTab("Troll")
local miscTab = window:AddTab("Misc")
local settingsTab = window:AddTab("Settings")

-- State --------------------------------------------------------------------

local PAGE_SIZE = 8

local state = {
    query = "",
    page = 1,
    selected = nil,
    spectating = nil,

    noclip = false,
    speedEnabled = false,
    walkSpeed = 16,
    jumpEnabled = false,
    jumpPower = 50,
    fly = false,
    flySpeed = 60,
    infiniteJump = false,
    frozen = false,

    esp = false,
    espNames = true,
    highlightSelected = false,
    fullbright = false,
    fog = false,
    fov = nil,

    followSelected = false,
    orbitSelected = false,
    orbitSpeed = 90,
    orbitDistance = 5,
    spin = false,
    spinSpeed = 720,
    ragdoll = false,
    dance = false,

    antiAfk = false,
}

-- Generic helpers ----------------------------------------------------------

local setClipboard = setclipboard or toclipboard

local function notify(message)
    pcall(function()
        library:SendNotification(tostring(message), 3)
    end)
end

-- Keep a toggle in sync when a feature turns itself off.
local function syncToggle(flag, value)
    pcall(function()
        local option = library.options and library.options[flag]
        if option and option.state ~= value then
            option:SetState(value, true)
        end
    end)
end

local function createInstance(className, properties, parent)
    local ok, instance = pcall(Instance.new, className)
    if not ok or not instance then
        return nil
    end
    for property, value in pairs(properties or {}) do
        pcall(function()
            instance[property] = value
        end)
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

local function getHumanoid(player)
    local character = (player or LocalPlayer).Character
    if not character then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        return humanoid
    end
    return nil
end

local function getRoot(player)
    local character = (player or LocalPlayer).Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root then
        return root
    end
    return character.PrimaryPart
end

-- The library freezes movement while a box is focused. Release it when we
-- leave the search box so WASD keeps working.
local function releaseMovement()
    pcall(function()
        ContextActionService:UnbindAction("FreezeMovement")
    end)
end

local accentMap = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["ç"] = "c", ["ñ"] = "n",
    ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Å"] = "a",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
    ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["Ç"] = "c", ["Ñ"] = "n",
}

local function normalize(value)
    value = string.lower(value)
    value = string.gsub(value, "^@", "")
    for accented, plain in pairs(accentMap) do
        value = string.gsub(value, accented, plain)
    end
    return value
end

local function truncate(value, limit)
    if not utf8 or not utf8.len then
        return value
    end
    local length = utf8.len(value)
    if not length or length <= limit then
        return value
    end
    local cut = utf8.offset(value, limit + 1)
    if not cut then
        return value
    end
    return string.sub(value, 1, cut - 1) .. "..."
end

local function matches(player, search)
    if search == "" then
        return true
    end
    if string.find(normalize(player.DisplayName), search, 1, true) then
        return true
    end
    if string.find(normalize(player.Name), search, 1, true) then
        return true
    end
    if string.find(tostring(player.UserId), search, 1, true) then
        return true
    end
    return false
end

local function rowText(player)
    local text = "@" .. player.Name
    if player.DisplayName ~= player.Name then
        text = text .. "  " .. player.DisplayName
    end
    if player == LocalPlayer then
        text = text .. "  (you)"
    end
    return truncate(text, 28)
end

-- ESP ----------------------------------------------------------------------

local espEntries = {}

local function highlightColor(player)
    if state.highlightSelected and state.selected == player then
        return Color3.fromRGB(0, 190, 255)
    end
    return Color3.fromRGB(255, 70, 70)
end

local function wantsHighlight(player)
    if player == LocalPlayer then
        return false
    end
    if state.esp then
        return true
    end
    return state.highlightSelected and state.selected == player
end

local function clearEspEntry(player)
    local entry = espEntries[player]
    if not entry then
        return
    end
    if entry.highlight then
        pcall(function()
            entry.highlight:Destroy()
        end)
    end
    if entry.billboard then
        pcall(function()
            entry.billboard:Destroy()
        end)
    end
    espEntries[player] = nil
end

local function refreshEspPlayer(player)
    if player == nil then
        return
    end

    local entry = espEntries[player]
    local wantHighlight = wantsHighlight(player)
    local wantName = state.esp and state.espNames and player ~= LocalPlayer

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid or humanoid.Health <= 0 then
        clearEspEntry(player)
        return
    end

    if not wantHighlight and not wantName then
        clearEspEntry(player)
        return
    end

    local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    if not root then
        clearEspEntry(player)
        return
    end

    entry = entry or {}
    espEntries[player] = entry

    if wantHighlight then
        if entry.highlight and entry.highlight.Parent ~= character then
            pcall(function()
                entry.highlight:Destroy()
            end)
            entry.highlight = nil
        end
        if not entry.highlight then
            entry.highlight = createInstance("Highlight", {
                Name = "thdreamsHighlight",
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                FillTransparency = 1,
                OutlineTransparency = 0,
                Adornee = character,
            }, character)
        end
        if entry.highlight then
            entry.highlight.Adornee = character
            entry.highlight.OutlineColor = highlightColor(player)
            entry.highlight.FillColor = highlightColor(player)
        end
    elseif entry.highlight then
        pcall(function()
            entry.highlight:Destroy()
        end)
        entry.highlight = nil
    end

    if wantName then
        if entry.billboard and entry.billboard.Parent ~= character then
            pcall(function()
                entry.billboard:Destroy()
            end)
            entry.billboard = nil
            entry.label = nil
        end
        if not entry.billboard then
            local billboard = createInstance("BillboardGui", {
                Name = "thdreamsESPName",
                Size = UDim2.new(0, 220, 0, 24),
                StudsOffset = Vector3.new(0, 3, 0),
                AlwaysOnTop = true,
                Adornee = root,
                LightInfluence = 0,
            }, character)
            local label = billboard and createInstance("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Font = Enum.Font.GothamBold,
                TextSize = 14,
                TextColor3 = Color3.fromRGB(255, 255, 255),
                TextStrokeTransparency = 0,
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                Text = "",
            }, billboard)
            entry.billboard = billboard
            entry.label = label
        end
        if entry.billboard then
            entry.billboard.Adornee = root
        end
        if entry.label then
            local camera = workspace.CurrentCamera
            local distance = 0
            if camera then
                distance = math.floor((camera.CFrame.Position - root.Position).Magnitude)
            end
            local text = "@" .. player.Name
            if player.DisplayName ~= player.Name then
                text = player.DisplayName .. " (@" .. player.Name .. ")"
            end
            entry.label.Text = truncate(text, 24) .. "  [" .. distance .. "m]"
        end
    elseif entry.billboard then
        pcall(function()
            entry.billboard:Destroy()
        end)
        entry.billboard = nil
        entry.label = nil
    end
end

local function refreshEspAll()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(refreshEspPlayer, player)
    end
    for player in pairs(espEntries) do
        if not player.Parent then
            clearEspEntry(player)
        end
    end
end

local function clearAllEsp()
    for player in pairs(espEntries) do
        clearEspEntry(player)
    end
end

-- Spectate -----------------------------------------------------------------

local spectateConnection

local updateActions
local spectateButton

-- Angles of the spectate orbit, in radians. Kept outside startSpectate so
-- swapping the spectated player does not reset the angle.
local spectateYaw = 0
local spectatePitch = math.rad(-10)
local spectateDistance = 12

-- GetMouseDelta only reports movement while the mouse is locked, so with a free
-- cursor (menu open, scriptable camera) it is mostly zero. Accumulate the
-- InputChanged deltas instead, and fall back to GetMouseDelta when the game
-- keeps the cursor locked.
local rightMouseDown = false
local leftMouseDown = false
local pendingDeltaX, pendingDeltaY = 0, 0
local pendingWheel = 0

-- The spectate camera is bound through BindToRenderStep so it runs *after* the
-- default CameraModule (RenderPriority.Camera) and after game cameras that bind
-- at Character. A plain RenderStepped connection can run before them, and then
-- the game's camera overwrote our CFrame (or forced its own CameraType) every
-- frame: the view snapped back to the frozen local character, which read as "the
-- mouse does not work", and two writers fighting over the camera made the wheel
-- zoom flicker.
local SPECTATE_STEP = "BlekSpectateCamera"
local spectateBoundStep = false
local spectateCameraGuard

local function spectateStepPriority()
    -- Last is the final camera slot, so games that drive the camera from their
    -- own high-priority render step still cannot overwrite ours afterwards.
    local ok, value = pcall(function()
        return Enum.RenderPriority.Last.Value
    end)
    if ok and type(value) == "number" then
        return value
    end
    local fallback = pcall(function()
        return Enum.RenderPriority.Camera.Value
    end)
    if fallback then
        return 2000
    end
    return nil
end

-- Point the spectate camera aims at. It used to be the head plus two studs,
-- which is where the name tag floats, so the camera framed the nameplate and
-- left the body hanging at the bottom of the screen.
local function spectateFocus(character)
    if not character then
        return nil
    end

    local part = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if part and part.Position then
        return part.Position
    end

    -- Custom rigs (skinned meshes, renamed parts) often have neither: fall back
    -- to the humanoid root, the primary part and finally the bounding box, so the
    -- camera still has something to orbit instead of freezing in place.
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.RootPart and humanoid.RootPart.Position then
        return humanoid.RootPart.Position
    end
    if character.PrimaryPart and character.PrimaryPart.Position then
        return character.PrimaryPart.Position
    end

    local ok, box = pcall(function()
        return character:GetBoundingBox()
    end)
    if ok and box then
        return box.Position
    end

    for _, child in ipairs(character:GetDescendants()) do
        if child:IsA("BasePart") then
            return child.Position
        end
    end
    return nil
end

local function restoreCamera()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    camera.CameraType = Enum.CameraType.Custom
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        camera.CameraSubject = humanoid
    end
end

-- Orbiting with the mouse needs a free cursor. Games that keep it locked (first
-- person, shift lock, some camlock systems) hide it and report deltas on an
-- axis the player cannot see, which is the other half of "the mouse does not
-- work": unlock it while spectating and put it back afterwards.
local cursorSaved = false
local savedMouseBehavior
local savedMouseIcon

local function unlockCursor()
    if not cursorSaved then
        cursorSaved = true
        local ok, behavior = pcall(function()
            return UserInputService.MouseBehavior
        end)
        if ok then
            savedMouseBehavior = behavior
        end
        -- Not `and/or`: a hidden cursor starts as false, which would be
        -- swallowed by that idiom.
        local okIcon, icon = pcall(function()
            return UserInputService.MouseIconEnabled
        end)
        if okIcon then
            savedMouseIcon = icon
        end
    end
    pcall(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end)
end

local function restoreCursor()
    if not cursorSaved then
        return
    end
    cursorSaved = false
    local behavior = savedMouseBehavior
    local icon = savedMouseIcon
    savedMouseBehavior, savedMouseIcon = nil, nil
    pcall(function()
        if behavior ~= nil then
            UserInputService.MouseBehavior = behavior
        end
        if icon ~= nil then
            UserInputService.MouseIconEnabled = icon
        end
    end)
end

-- While spectating the camera is detached, so the local character has to stay
-- put: walking, jumping or a leftover fly would move a body the player cannot
-- see. The values are saved once and put back when spectating ends.
local spectateMovement

local function lockLocalMovement()
    local humanoid = getHumanoid(LocalPlayer)
    local root = getRoot(LocalPlayer)

    if humanoid and not spectateMovement then
        spectateMovement = {
            walkSpeed = humanoid.WalkSpeed,
            jumpPower = humanoid.JumpPower,
            jumpHeight = humanoid.JumpHeight,
        }
    end

    if humanoid then
        pcall(function()
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.JumpHeight = 0
            humanoid.Jump = false
        end)
    end
    if root then
        pcall(function()
            root.Anchored = true
        end)
    end
end

local function unlockLocalMovement()
    local humanoid = getHumanoid(LocalPlayer)
    local root = getRoot(LocalPlayer)
    local backup = spectateMovement
    spectateMovement = nil

    if root then
        pcall(function()
            -- The Freeze toggle owns the anchor; spectating only borrows it.
            root.Anchored = state.frozen == true
        end)
    end

    if humanoid then
        pcall(function()
            if state.speedEnabled then
                humanoid.WalkSpeed = state.walkSpeed
            else
                humanoid.WalkSpeed = (backup and backup.walkSpeed) or 16
            end

            if state.jumpEnabled then
                if humanoid.UseJumpPower then
                    humanoid.JumpPower = state.jumpPower
                else
                    humanoid.JumpHeight = state.jumpPower * 0.144
                end
            elseif backup then
                humanoid.JumpPower = backup.jumpPower
                humanoid.JumpHeight = backup.jumpHeight
            end
        end)
    end
end

local function stopSpectate(silent)
    if spectateCameraGuard then
        pcall(function()
            spectateCameraGuard:Disconnect()
        end)
        spectateCameraGuard = nil
    end
    if spectateBoundStep then
        pcall(function()
            RunService:UnbindFromRenderStep(SPECTATE_STEP)
        end)
        spectateBoundStep = false
    end
    if spectateConnection then
        pcall(function()
            spectateConnection:Disconnect()
        end)
        spectateConnection = nil
    end
    pendingDeltaX, pendingDeltaY = 0, 0
    pendingWheel = 0
    local wasSpectating = state.spectating ~= nil
    state.spectating = nil
    if wasSpectating then
        unlockLocalMovement()
    end
    restoreCamera()
    restoreCursor()
    if wasSpectating and not silent then
        notify("Spectating stopped.")
    end
    if updateActions then
        updateActions()
    end
end

local function resetCamera()
    if state.spectating then
        stopSpectate(true)
    end
    restoreCamera()
    notify("Camera restored.")
end

local function startSpectate(player, quiet)
    if player == nil then
        if not quiet then
            notify("Select a player first.")
        end
        return
    end
    if player == LocalPlayer then
        notify("You cannot spectate yourself.")
        return
    end
    if not player.Character then
        notify("That player has no character right now.")
        return
    end

    stopSpectate(true)

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    -- Start from the angle we already look at the target from, so the camera
    -- does not jump.
    local character = player.Character
    local focus = spectateFocus(character)
    if focus then
        local offset = camera.CFrame.Position - focus
        if offset.Magnitude > 0.5 then
            spectateDistance = math.clamp(offset.Magnitude, 5, 80)
            spectateYaw = math.atan2(offset.X, offset.Z)
            spectatePitch = math.asin(math.clamp(offset.Unit.Y, -1, 1))
        end
    end

    state.spectating = player
    camera.CameraType = Enum.CameraType.Scriptable
    lockLocalMovement()
    unlockCursor()
    pendingDeltaX, pendingDeltaY = 0, 0
    pendingWheel = 0

    local function updateSpectate(delta)
        if not active or state.spectating ~= player then
            return
        end

        local currentCamera = workspace.CurrentCamera
        if not currentCamera then
            return
        end
        currentCamera.CameraType = Enum.CameraType.Scriptable

        -- Games and respawns reset these at any time; enforce them every frame
        -- so the character cannot be walked away while the camera is detached.
        local idle = getHumanoid(LocalPlayer)
        if idle then
            if idle.WalkSpeed ~= 0 then
                idle.WalkSpeed = 0
            end
            if idle.JumpPower ~= 0 then
                idle.JumpPower = 0
            end
            if idle.JumpHeight ~= 0 then
                idle.JumpHeight = 0
            end
            if idle.Jump then
                idle.Jump = false
            end
        end
        local idleRoot = getRoot(LocalPlayer)
        if idleRoot and not idleRoot.Anchored then
            idleRoot.Anchored = true
        end

        -- Mouse look. Moving the mouse orbits even without a button held: that is
        -- what a spectate camera is expected to do, and it keeps working in games
        -- that swallow the right button or keep the cursor captured.
        local dragging = rightMouseDown or leftMouseDown
        local moveX, moveY = pendingDeltaX, pendingDeltaY
        pendingDeltaX, pendingDeltaY = 0, 0
        if moveX == 0 and moveY == 0 then
            -- Locked cursor (first person, shift lock, camlock): the pointer does
            -- not move, so only the raw per-frame delta reports the mouse.
            local ok, raw = pcall(function()
                return UserInputService:GetMouseDelta()
            end)
            if ok and raw then
                moveX, moveY = raw.X or 0, raw.Y or 0
            end
        end
        -- Always look around: no button, no need to keep the pointer off the
        -- window. Anything conditional here was another way to end up with a
        -- camera that did not move. A drag is a bit faster, like the default
        -- camera.
        local sensitivity = dragging and 0.005 or 0.0035
        spectateYaw = spectateYaw - moveX * sensitivity
        spectatePitch = spectatePitch + moveY * sensitivity

        -- One zoom step per frame, however many wheel events arrived.
        if pendingWheel ~= 0 then
            spectateDistance = math.clamp(spectateDistance - pendingWheel * 2, 4, 100)
            pendingWheel = 0
        end

        -- Arrow keys work too, for players who drive the camera from the keyboard.
        local arrowYaw = math.rad(120) * delta
        local arrowPitch = math.rad(90) * delta
        if UserInputService:IsKeyDown(Enum.KeyCode.Left) then
            spectateYaw = spectateYaw + arrowYaw
        elseif UserInputService:IsKeyDown(Enum.KeyCode.Right) then
            spectateYaw = spectateYaw - arrowYaw
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Up) then
            spectatePitch = spectatePitch - arrowPitch
        elseif UserInputService:IsKeyDown(Enum.KeyCode.Down) then
            spectatePitch = spectatePitch + arrowPitch
        end
        spectatePitch = math.clamp(spectatePitch, math.rad(-85), math.rad(85))

        local focus = spectateFocus(player.Character)
        if not focus then
            return
        end

        local cosPitch = math.cos(spectatePitch)
        local offset = Vector3.new(
            math.sin(spectateYaw) * cosPitch,
            math.sin(spectatePitch),
            math.cos(spectateYaw) * cosPitch
        ) * spectateDistance
        currentCamera.CFrame = CFrame.lookAt(focus + offset, focus)
    end

    local priority = spectateStepPriority()
    if priority then
        local bound = pcall(function()
            RunService:BindToRenderStep(SPECTATE_STEP, priority, updateSpectate)
        end)
        if not bound then
            -- A previous run of this script can leave the name bound to a dead
            -- closure, which would keep writing the camera with stale angles and
            -- make the view look frozen. Take the name over.
            pcall(function()
                RunService:UnbindFromRenderStep(SPECTATE_STEP)
            end)
            bound = pcall(function()
                RunService:BindToRenderStep(SPECTATE_STEP, priority, updateSpectate)
            end)
        end
        spectateBoundStep = bound == true
    end
    if not spectateBoundStep then
        -- Executors without BindToRenderStep: still works, only without the
        -- ordering guarantee over the game camera.
        spectateConnection = track(RunService.RenderStepped:Connect(updateSpectate))
    end

    -- Games switch back to their own camera type at any time (respawn, seats,
    -- first person). Put it straight back instead of waiting for the next frame.
    pcall(function()
        spectateCameraGuard = camera:GetPropertyChangedSignal("CameraType"):Connect(function()
            if active and state.spectating == player and camera.CameraType ~= Enum.CameraType.Scriptable then
                camera.CameraType = Enum.CameraType.Scriptable
            end
        end)
    end)

    if not quiet then
        notify("Spectating @" .. player.Name .. ". Move the mouse to look, wheel to zoom.")
    end
    if updateActions then
        updateActions()
    end
end

-- Button state and pointer movement for the spectate orbit, plus the mouse
-- wheel zoom. Everything is accumulated here and applied once per frame in the
-- camera step.
track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rightMouseDown = true
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not gameProcessed then
        -- Left-drag outside the menu orbits too, in case something eats the
        -- right button.
        leftMouseDown = true
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rightMouseDown = false
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        leftMouseDown = false
    end
    if not rightMouseDown and not leftMouseDown then
        pendingDeltaX, pendingDeltaY = 0, 0
    end
end))

track(UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if not active or not state.spectating then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        -- Every movement counts: the camera step decides whether it orbits (the
        -- pointer is over the 3D view) or belongs to the menu.
        local delta = input.Delta
        if delta then
            pendingDeltaX = pendingDeltaX + (delta.X or 0)
            pendingDeltaY = pendingDeltaY + (delta.Y or 0)
        end
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        -- Over the window the wheel scrolls the menu, nothing else.
        if gameProcessed or pointerOverMenu() then
            return
        end
        local notch = (input.Position and input.Position.Z) or (input.Delta and input.Delta.Z) or 0
        if type(notch) == "number" then
            pendingWheel = pendingWheel + notch
        end
    end
end))

-- Movement -----------------------------------------------------------------

local noclipBackup = {}

local function setNoclip(on)
    state.noclip = on
    if on then
        return
    end
    for part in pairs(noclipBackup) do
        if typeof(part) == "Instance" and part.Parent then
            pcall(function()
                part.CanCollide = true
            end)
        end
    end
    noclipBackup = {}
end

local function applySpeed()
    local humanoid = getHumanoid(LocalPlayer)
    if humanoid and state.speedEnabled then
        humanoid.WalkSpeed = state.walkSpeed
    end
end

local function applyJump()
    local humanoid = getHumanoid(LocalPlayer)
    if not humanoid or not state.jumpEnabled then
        return
    end
    if humanoid.UseJumpPower then
        humanoid.JumpPower = state.jumpPower
    else
        humanoid.JumpHeight = state.jumpPower * 0.144
    end
end

-- Fly keeps its own position: reading the part back every frame would let
-- gravity pull the character down a little each step.
local flyPosition

local function setFly(on)
    state.fly = on
    local root = getRoot(LocalPlayer)
    flyPosition = on and root and root.Position or nil
    local humanoid = getHumanoid(LocalPlayer)
    if humanoid then
        pcall(function()
            humanoid.PlatformStand = on
        end)
    end
end

local function setFreeze(on)
    state.frozen = on
    local root = getRoot(LocalPlayer)
    if root then
        pcall(function()
            root.Anchored = on
        end)
    end
end

local function teleportTo(player)
    if player == nil then
        notify("Select a player first.")
        return
    end
    if player == LocalPlayer then
        notify("That is you.")
        return
    end
    local myRoot = getRoot(LocalPlayer)
    local targetRoot = getRoot(player)
    if not myRoot then
        notify("Your character is not spawned.")
        return
    end
    if not targetRoot then
        notify("That player has no character right now.")
        return
    end
    local character = LocalPlayer.Character
    local ok = pcall(function()
        character:PivotTo(targetRoot.CFrame)
    end)
    if not ok then
        pcall(function()
            myRoot.CFrame = targetRoot.CFrame
        end)
    end
    notify("Teleported to @" .. player.Name .. ".")
end

-- Troll -------------------------------------------------------------------

local orbitAngle = 0
local danceTrack

local function getSelectedRoot()
    local player = state.selected
    if not player then
        return nil, nil
    end
    local character = player.Character
    if not character then
        return nil, nil
    end
    return character, character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function flingRoot(root)
    if not root then
        return false
    end
    local ok = pcall(function()
        root.AssemblyAngularVelocity = Vector3.new(1e4, 1e4, 1e4)
        root.AssemblyLinearVelocity = Vector3.zero
    end)
    if ok then
        task.delay(0.6, function()
            pcall(function()
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end)
    end
    return ok
end

-- Flinging only shows up when the character collides with the world, so
-- force collisions on before spinning it.
local function prepareForFling(character)
    if not character then
        return
    end
    pcall(function()
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end)
end

local function flingSelected()
    local targetCharacter, targetRoot = getSelectedRoot()
    if not targetRoot then
        notify("Select a player with a spawned character first.")
        return
    end
    prepareForFling(targetCharacter)
    local owner
    pcall(function()
        owner = targetRoot:GetNetworkOwner()
    end)
    if owner ~= nil and owner ~= LocalPlayer then
        notify("That player owns their character; this game may ignore the fling.")
    else
        notify("Flinging @" .. state.selected.Name .. ".")
    end
    flingRoot(targetRoot)
end

local function flingSelf()
    local root = getRoot(LocalPlayer)
    if not root then
        notify("Your character is not spawned.")
        return
    end
    flingRoot(root)
    notify("Flinging yourself.")
end

local function setSpin(on)
    state.spin = on
    local humanoid = getHumanoid(LocalPlayer)
    if humanoid then
        pcall(function()
            humanoid.AutoRotate = not on
        end)
    end
end

local function setRagdoll(on)
    state.ragdoll = on
    local humanoid = getHumanoid(LocalPlayer)
    if humanoid then
        pcall(function()
            humanoid.Sit = false
            humanoid.PlatformStand = on
        end)
    end
end

local function setSit(on)
    local humanoid = getHumanoid(LocalPlayer)
    if not humanoid then
        notify("Your character is not spawned.")
        return
    end
    if state.ragdoll then
        state.ragdoll = false
        syncToggle("troll_ragdoll", false)
    end
    pcall(function()
        humanoid.PlatformStand = false
        humanoid.Sit = on
    end)
end

local function stopDance()
    if danceTrack then
        pcall(function()
            danceTrack:Stop()
        end)
        danceTrack = nil
    end
end

local function setDance(on)
    state.dance = on
    stopDance()
    if not on then
        return
    end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        state.dance = false
        syncToggle("troll_dance", false)
        notify("Your character is not spawned.")
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = createInstance("Animator", {}, humanoid)
    end
    if not animator then
        state.dance = false
        syncToggle("troll_dance", false)
        notify("Could not create an Animator.")
        return
    end

    local animation = createInstance("Animation", { AnimationId = "rbxassetid://507771019" })
    local ok, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if not ok or not track then
        state.dance = false
        syncToggle("troll_dance", false)
        notify("This executor could not load the dance animation.")
        return
    end
    pcall(function()
        track:Play()
    end)
    danceTrack = track
end

local function trollTick(delta)
    local myCharacter = LocalPlayer.Character
    if not myCharacter then
        return
    end

    -- Follow and orbit drag the body around; that has to stop while the camera
    -- is spectating with the character frozen.
    if (state.followSelected or state.orbitSelected) and not state.spectating then
        local _, targetRoot = getSelectedRoot()
        if targetRoot then
            if state.followSelected then
                pcall(function()
                    local root = getRoot(LocalPlayer)
                    if not root then
                        return
                    end
                    -- Only jump when left behind, so walking next to the target
                    -- does not stutter.
                    if (root.Position - targetRoot.Position).Magnitude < 6 then
                        return
                    end
                    root.AssemblyLinearVelocity = Vector3.zero
                    myCharacter:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 4))
                end)
            elseif state.orbitSelected then
                orbitAngle = orbitAngle + math.rad(state.orbitSpeed) * delta
                local offset = Vector3.new(
                    math.cos(orbitAngle) * state.orbitDistance,
                    2.5,
                    math.sin(orbitAngle) * state.orbitDistance
                )
                local position = targetRoot.Position + offset
                pcall(function()
                    local root = getRoot(LocalPlayer)
                    if root then
                        root.AssemblyLinearVelocity = Vector3.zero
                    end
                    myCharacter:PivotTo(CFrame.lookAt(position, targetRoot.Position))
                end)
            end
        end
    end

    if state.spin then
        local root = getRoot(LocalPlayer)
        if root then
            pcall(function()
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(state.spinSpeed) * delta, 0)
            end)
        end
    end
end

-- Lighting -----------------------------------------------------------------

local lightingBackup
local fogBackup

local function setFullbright(on)
    state.fullbright = on
    if on then
        if not lightingBackup then
            lightingBackup = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                GlobalShadows = Lighting.GlobalShadows,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    elseif lightingBackup then
        pcall(function()
            Lighting.Brightness = lightingBackup.Brightness
            Lighting.ClockTime = lightingBackup.ClockTime
            Lighting.GlobalShadows = lightingBackup.GlobalShadows
            Lighting.Ambient = lightingBackup.Ambient
            Lighting.OutdoorAmbient = lightingBackup.OutdoorAmbient
        end)
        lightingBackup = nil
    end
end

local function setFog(on)
    state.fog = on
    if on then
        if not fogBackup then
            fogBackup = {
                FogStart = Lighting.FogStart,
                FogEnd = Lighting.FogEnd,
            }
        end
        Lighting.FogStart = 0
        Lighting.FogEnd = 1e7
    elseif fogBackup then
        pcall(function()
            Lighting.FogStart = fogBackup.FogStart
            Lighting.FogEnd = fogBackup.FogEnd
        end)
        fogBackup = nil
    end
end

local originalFov

local function setFov(value)
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    if not originalFov then
        originalFov = camera.FieldOfView
    end
    state.fov = value
    camera.FieldOfView = value
end

local function resetFov()
    local camera = workspace.CurrentCamera
    if originalFov and camera then
        camera.FieldOfView = originalFov
    end
    originalFov = nil
    state.fov = nil
end

-- Server helpers -----------------------------------------------------------

local function copyText(value, label)
    if not setClipboard then
        notify("This executor has no clipboard function.")
        return
    end
    local ok = pcall(setClipboard, value)
    if ok then
        notify(label .. " copied.")
    else
        notify("Could not copy to the clipboard.")
    end
end

local function jobId()
    if game.JobId ~= nil and game.JobId ~= "" then
        return game.JobId
    end
    return "Studio / private server"
end

-- Cleanup ------------------------------------------------------------------

local function restoreEverything()
    state.followSelected = false
    state.orbitSelected = false
    setSpin(false)
    setRagdoll(false)
    setDance(false)
    setNoclip(false)
    setFly(false)
    setFreeze(false)
    setFullbright(false)
    setFog(false)
    resetFov()
    stopSpectate(true)
    restoreCamera()
    clearAllEsp()

    local humanoid = getHumanoid(LocalPlayer)
    if humanoid then
        pcall(function()
            humanoid.Sit = false
        end)
    end
    if humanoid then
        pcall(function()
            if state.speedEnabled then
                humanoid.WalkSpeed = 16
            end
            if state.jumpEnabled then
                if humanoid.UseJumpPower then
                    humanoid.JumpPower = 50
                else
                    humanoid.JumpHeight = 7.2
                end
            end
        end)
    end
end

local function cleanup(unloadLibrary)
    if not active then
        return
    end
    active = false

    pcall(restoreEverything)

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    connections = {}

    pcall(function()
        ContextActionService:UnbindAction("FreezeMovement")
    end)

    if env.TokyoMultitoolCleanup ~= nil then
        env.TokyoMultitoolCleanup = nil
    end
    env.TokyoMultitoolRender = nil
    env.TokyoMultitoolNextPage = nil
    env.TokyoMultitoolSelect = nil

    pcall(function()
        if toastGui then
            toastGui:Destroy()
        end
    end)

    pcall(function()
        if miniGui then
            miniGui:Destroy()
        end
        miniGui = nil
        miniButton = nil
    end)

    if unloadLibrary then
        pcall(function()
            library:Unload()
        end)
    end
end

-- UI: Players --------------------------------------------------------------

local searchBox

local function resetSearch()
    state.query = ""
    state.page = 1
    pcall(function()
        searchBox:SetInput("", true)
        searchBox:ReleaseFocus()
    end)
    releaseMovement()
    if env.TokyoMultitoolRender then
        env.TokyoMultitoolRender()
    end
end

local listSection = playersTab:AddSection("Player List", 1)
local listSummary = listSection:AddText({
    text = "Loading...",
})

local rowButtons = {}
local currentRows = {}

for slot = 1, PAGE_SIZE do
    rowButtons[slot] = listSection:AddButton({
        text = "",
        callback = function()
            local player = currentRows[slot]
            if player then
                local selectPlayer = env.TokyoMultitoolSelect
                if selectPlayer then
                    selectPlayer(player)
                end
            end
        end,
    })
end

listSection:AddText({
    text = "Click a row to select a player.",
})

local pager = listSection:AddButton({ text = "" })
pager:AddButton({
    text = "Previous",
    callback = function()
        if state.page > 1 then
            state.page = state.page - 1
            if env.TokyoMultitoolRender then
                env.TokyoMultitoolRender()
            end
        end
    end,
})
pager:AddButton({
    text = "Next",
    callback = function()
        if env.TokyoMultitoolNextPage then
            env.TokyoMultitoolNextPage()
        end
    end,
})

local searchSection = playersTab:AddSection("Search", 2)
searchBox = searchSection:AddBox({
    text = "Search player",
    tooltip = "Display name, @username or user ID",
    callback = function(value)
        state.query = value
        state.page = 1
        releaseMovement()
        if env.TokyoMultitoolRender then
            env.TokyoMultitoolRender()
        end
    end,
})
searchSection:AddText({
    text = "Type to filter by name, @user or ID.",
})
searchSection:AddButton({
    text = "Clear Search",
    callback = function()
        -- Deferred so it wins over the box applying its text on click.
        task.defer(resetSearch)
    end,
})

local actionsSection = playersTab:AddSection("Actions", 2)
local selectedText = actionsSection:AddText({
    text = "Selected: none",
})
local spectateText = actionsSection:AddText({
    text = "Spectating: none",
})
actionsSection:AddText({
    text = "Spectate: move the mouse or drag to look, wheel to zoom.",
})

-- One button with two modes: starts spectating, then stops it.
spectateButton = actionsSection:AddButton({
    text = "Spectate: Inactive",
    callback = function()
        if state.spectating then
            stopSpectate(false)
        else
            startSpectate(state.selected)
        end
    end,
})
actionsSection:AddButton({
    text = "Teleport To",
    callback = function()
        teleportTo(state.selected)
    end,
})
actionsSection:AddToggle({
    text = "Highlight Selected",
    flag = "highlight_selected",
    callback = function(on)
        state.highlightSelected = on
        refreshEspAll()
    end,
})
actionsSection:AddButton({
    text = "Copy Username",
    callback = function()
        if state.selected then
            copyText(state.selected.Name, "Username")
        else
            notify("Select a player first.")
        end
    end,
})
actionsSection:AddButton({
    text = "Copy User ID",
    callback = function()
        if state.selected then
            copyText(tostring(state.selected.UserId), "User ID")
        else
            notify("Select a player first.")
        end
    end,
})

playersTab:UpdateSections()

-- UI: Movement -------------------------------------------------------------

local movementSection = movementTab:AddSection("Movement", 1)

movementSection:AddToggle({
    text = "Noclip",
    flag = "noclip",
    callback = function(on)
        setNoclip(on)
        notify(on and "Noclip enabled." or "Noclip disabled.")
    end,
})
movementSection:AddToggle({
    text = "Infinite Jump",
    flag = "infinite_jump",
    callback = function(on)
        state.infiniteJump = on
    end,
})
movementSection:AddToggle({
    text = "Freeze Character",
    flag = "freeze",
    callback = function(on)
        setFreeze(on)
    end,
})

local speedSection = movementTab:AddSection("Speed & Jump", 1)

speedSection:AddToggle({
    text = "Speed",
    flag = "speed",
    callback = function(on)
        state.speedEnabled = on
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid then
            humanoid.WalkSpeed = on and state.walkSpeed or 16
        end
    end,
})
speedSection:AddSlider({
    text = "Walk Speed",
    flag = "walk_speed",
    value = 16,
    min = 8,
    max = 250,
    increment = 1,
    callback = function(value)
        state.walkSpeed = value
        if state.speedEnabled then
            applySpeed()
        end
    end,
})

speedSection:AddToggle({
    text = "Jump Boost",
    flag = "jump_boost",
    callback = function(on)
        state.jumpEnabled = on
        if not on then
            local humanoid = getHumanoid(LocalPlayer)
            if humanoid then
                if humanoid.UseJumpPower then
                    humanoid.JumpPower = 50
                else
                    humanoid.JumpHeight = 7.2
                end
            end
        end
    end,
})
speedSection:AddSlider({
    text = "Jump Power",
    flag = "jump_power",
    value = 50,
    min = 50,
    max = 500,
    increment = 5,
    callback = function(value)
        state.jumpPower = value
        applyJump()
    end,
})

local flySection = movementTab:AddSection("Fly", 2)

flySection:AddToggle({
    text = "Fly",
    flag = "fly",
    callback = function(on)
        setFly(on)
        notify(on and "Fly enabled." or "Fly disabled.")
    end,
})
flySection:AddSlider({
    text = "Fly Speed",
    flag = "fly_speed",
    value = 60,
    min = 20,
    max = 300,
    increment = 5,
    callback = function(value)
        state.flySpeed = value
    end,
})
flySection:AddText({
    text = "WASD moves, Space up, LeftCtrl down.",
})
flySection:AddText({
    text = "Hold LeftShift to go faster.",
})

movementTab:UpdateSections()

-- UI: Visuals --------------------------------------------------------------

local espSection = visualsTab:AddSection("Player ESP", 1)

espSection:AddToggle({
    text = "Player ESP",
    flag = "esp",
    callback = function(on)
        state.esp = on
        refreshEspAll()
    end,
})
local espNamesToggle = espSection:AddToggle({
    text = "ESP Names",
    flag = "esp_names",
    callback = function(on)
        state.espNames = on
        refreshEspAll()
    end,
})
espNamesToggle:SetState(true, true)
espSection:AddText({
    text = "Outlines are visible through walls.",
})

local environmentSection = visualsTab:AddSection("Environment", 2)

environmentSection:AddToggle({
    text = "Fullbright",
    flag = "fullbright",
    callback = function(on)
        setFullbright(on)
    end,
})
environmentSection:AddToggle({
    text = "Remove Fog",
    flag = "remove_fog",
    callback = function(on)
        setFog(on)
    end,
})
environmentSection:AddSlider({
    text = "Field of View",
    flag = "fov",
    value = 70,
    min = 40,
    max = 120,
    increment = 1,
    callback = function(value)
        setFov(value)
    end,
})
environmentSection:AddButton({
    text = "Reset FOV",
    callback = function()
        resetFov()
        notify("Field of view restored.")
    end,
})

visualsTab:UpdateSections()

-- UI: Troll ----------------------------------------------------------------

local targetTrollSection = trollTab:AddSection("Selected Player", 1)

targetTrollSection:AddToggle({
    text = "Follow Selected",
    flag = "troll_follow",
    callback = function(on)
        state.followSelected = on
    end,
})
targetTrollSection:AddToggle({
    text = "Orbit Selected",
    flag = "troll_orbit",
    callback = function(on)
        state.orbitSelected = on
    end,
})
targetTrollSection:AddSlider({
    text = "Orbit Distance",
    flag = "troll_orbit_distance",
    value = 5,
    min = 3,
    max = 20,
    increment = 1,
    callback = function(value)
        state.orbitDistance = value
    end,
})
targetTrollSection:AddSlider({
    text = "Orbit Speed",
    flag = "troll_orbit_speed",
    value = 90,
    min = 30,
    max = 360,
    increment = 10,
    callback = function(value)
        state.orbitSpeed = value
    end,
})
targetTrollSection:AddButton({
    text = "Fling Selected",
    callback = flingSelected,
})
targetTrollSection:AddText({
    text = "Follow and Orbit need a selected player.",
})

local selfTrollSection = trollTab:AddSection("Your Character", 2)

selfTrollSection:AddToggle({
    text = "Spin",
    flag = "troll_spin",
    callback = function(on)
        setSpin(on)
    end,
})
selfTrollSection:AddSlider({
    text = "Spin Speed",
    flag = "troll_spin_speed",
    value = 720,
    min = 180,
    max = 1440,
    increment = 60,
    callback = function(value)
        state.spinSpeed = value
    end,
})
selfTrollSection:AddToggle({
    text = "Ragdoll",
    flag = "troll_ragdoll",
    callback = function(on)
        setRagdoll(on)
    end,
})
selfTrollSection:AddToggle({
    text = "Dance",
    flag = "troll_dance",
    callback = function(on)
        setDance(on)
    end,
})
selfTrollSection:AddButton({
    text = "Sit",
    callback = function()
        setSit(true)
    end,
})
selfTrollSection:AddButton({
    text = "Stand",
    callback = function()
        setSit(false)
    end,
})
selfTrollSection:AddButton({
    text = "Fling Self",
    callback = flingSelf,
})
selfTrollSection:AddText({
    text = "Flinging others only works when you own their parts.",
})

trollTab:UpdateSections()

-- UI: Misc ----------------------------------------------------------------

local characterSection = miscTab:AddSection("Character", 1)

characterSection:AddButton({
    text = "Reset Character",
    callback = function()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Health = 0
        end
    end,
})
characterSection:AddButton({
    text = "Rejoin Server",
    callback = function()
        notify("Rejoining...")
        pcall(function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end)
    end,
})
characterSection:AddButton({
    text = "Reset Camera",
    callback = resetCamera,
})
characterSection:AddToggle({
    text = "Anti-AFK",
    flag = "anti_afk",
    callback = function(on)
        state.antiAfk = on
    end,
})

local serverSection = miscTab:AddSection("Server", 2)

local serverPlayersText = serverSection:AddText({
    text = "Players: 0",
})
local serverJobText = serverSection:AddText({
    text = "Job ID: loading...",
})

serverSection:AddButton({
    text = "Copy Job ID",
    callback = function()
        copyText(jobId(), "Job ID")
    end,
})
serverSection:AddButton({
    text = "Copy Place ID",
    callback = function()
        copyText(tostring(game.PlaceId), "Place ID")
    end,
})

miscTab:UpdateSections()

-- UI: Settings -------------------------------------------------------------

local menuSection = settingsTab:AddSection("Menu", 1)

menuSection:AddText({
    text = "RightShift opens / closes the menu.",
})
menuSection:AddButton({
    text = "Reset Camera",
    callback = resetCamera,
})
menuSection:AddButton({
    text = "Close Menu",
    callback = function()
        setMenuOpen(false)
    end,
})
menuSection:AddButton({
    text = "Unload Menu",
    callback = function()
        cleanup(true)
    end,
})

settingsTab:UpdateSections()

-- Player list rendering ----------------------------------------------------

local totalMatches = 0

local function render()
    local allPlayers = Players:GetPlayers()
    table.sort(allPlayers, function(a, b)
        return normalize(a.DisplayName) < normalize(b.DisplayName)
    end)

    local search = normalize(state.query)
    local filtered = {}
    for _, player in ipairs(allPlayers) do
        if matches(player, search) then
            table.insert(filtered, player)
        end
    end

    totalMatches = #filtered
    local pages = math.max(1, math.ceil(totalMatches / PAGE_SIZE))
    state.page = math.clamp(state.page, 1, pages)

    local firstIndex = (state.page - 1) * PAGE_SIZE + 1
    local lastIndex = math.min(state.page * PAGE_SIZE, totalMatches)

    if totalMatches == 0 then
        listSummary:SetText(#allPlayers == 0 and "No players in this server." or "No players match your search.")
    else
        listSummary:SetText(("Showing %d-%d of %d"):format(firstIndex, lastIndex, totalMatches))
    end

    currentRows = {}
    for slot = 1, PAGE_SIZE do
        local player = filtered[firstIndex + slot - 1]
        local row = rowButtons[slot]
        if player then
            currentRows[slot] = player
            row.enabled = true
            local text = rowText(player)
            if state.selected == player then
                text = "> " .. text
            end
            row:SetText(text)
        else
            row.enabled = false
        end
    end
    listSection:UpdateOptions()

    serverPlayersText:SetText("Players: " .. tostring(#allPlayers))
    local id = jobId()
    serverJobText:SetText("Job ID: " .. truncate(id, 26))
end

function updateActions()
    if state.selected then
        selectedText:SetText("Selected: @" .. truncate(state.selected.Name, 16))
    else
        selectedText:SetText("Selected: none")
    end
    if state.spectating then
        spectateText:SetText("Spectating: @" .. truncate(state.spectating.Name, 16))
    else
        spectateText:SetText("Spectating: none")
    end

    if spectateButton then
        spectateButton:SetText(state.spectating and "Spectate: Active" or "Spectate: Inactive")
        pcall(function()
            spectateButton.objects.text.TextColor3 = state.spectating
                and Color3.fromRGB(32, 202, 106)
                or TEXT_COLOR
        end)
    end
end

local function selectPlayer(player)
    state.selected = player
    updateActions()
    refreshEspAll()
    render()

    -- While spectating, picking someone else in the list switches the camera.
    if state.spectating and state.spectating ~= player then
        if player == nil or player == LocalPlayer then
            stopSpectate(false)
        elseif player.Character then
            startSpectate(player, true)
        else
            notify("That player has no character right now.")
        end
    end
end

local function nextPage()
    local pages = math.max(1, math.ceil(totalMatches / PAGE_SIZE))
    if state.page < pages then
        state.page = state.page + 1
        render()
    end
end

env.TokyoMultitoolRender = render
env.TokyoMultitoolNextPage = nextPage
env.TokyoMultitoolSelect = selectPlayer

-- Live input ---------------------------------------------------------------

track(UserInputService.InputBegan:Connect(function(input, processed)
    -- RightShift toggles the menu even while a text box has focus.
    if input.KeyCode == Enum.KeyCode.RightShift then
        if searchBox.focused then
            searchBox:ReleaseFocus()
            releaseMovement()
        end
        setMenuOpen(not menuOpen)
        return
    end

    if processed then
        return
    end

    if input.KeyCode == Enum.KeyCode.Space and state.infiniteJump and not state.spectating then
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Escape then
        task.defer(releaseMovement)
    end

    -- Filter as the user types, using the text the library already rendered.
    if searchBox.focused then
        task.defer(function()
            if searchBox.focused then
                state.query = searchBox.objects.inputText.Text
                state.page = 1
                render()
            end
        end)
    end
end))

-- Loops --------------------------------------------------------------------

-- Noclip, fly and the value enforcers.
track(RunService.Stepped:Connect(function()
    if not active then
        return
    end

    if state.noclip then
        local character = LocalPlayer.Character
        if character then
            for _, descendant in ipairs(character:GetDescendants()) do
                if descendant:IsA("BasePart") and descendant.CanCollide then
                    noclipBackup[descendant] = true
                    descendant.CanCollide = false
                end
            end
        end
    end
end))

track(RunService.RenderStepped:Connect(function(delta)
    if not active then
        return
    end

    -- Fly, speed and jump stay off while spectating; the camera follows someone
    -- else and the local character is frozen by the spectate loop.
    if state.fly and not state.spectating then
        local root = getRoot(LocalPlayer)
        local camera = workspace.CurrentCamera
        if root and camera then
            local direction = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                direction = direction + camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                direction = direction - camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                direction = direction + camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                direction = direction - camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                direction = direction + Vector3.yAxis
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                direction = direction - Vector3.yAxis
            end

            if direction.Magnitude > 0 then
                direction = direction.Unit
            end

            local speed = state.flySpeed
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                speed = speed * 2
            end

            local step = direction * speed * math.min(delta, 0.1)
            pcall(function()
                local current = root.CFrame
                if not flyPosition or (current.Position - flyPosition).Magnitude > 25 then
                    -- Resync after a teleport or respawn instead of snapping back.
                    flyPosition = current.Position
                end
                flyPosition = flyPosition + step
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = CFrame.new(flyPosition) * (current - current.Position)
            end)
        end
    end

    if state.speedEnabled and not state.spectating then
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid and math.abs(humanoid.WalkSpeed - state.walkSpeed) > 0.01 then
            humanoid.WalkSpeed = state.walkSpeed
        end
    end

    if state.jumpEnabled and not state.spectating then
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid then
            if humanoid.UseJumpPower then
                if humanoid.JumpPower ~= state.jumpPower then
                    humanoid.JumpPower = state.jumpPower
                end
            elseif math.abs(humanoid.JumpHeight - state.jumpPower * 0.144) > 0.01 then
                humanoid.JumpHeight = state.jumpPower * 0.144
            end
        end
    end

    if state.fov then
        local camera = workspace.CurrentCamera
        if camera and math.abs(camera.FieldOfView - state.fov) > 0.01 then
            camera.FieldOfView = state.fov
        end
    end

    pcall(trollTick, delta)
end))

-- Refreshes ESP, the highlight and the server panel a few times a second.
track(task.spawn(function()
    while active do
        task.wait(0.4)
        if not active then
            break
        end
        pcall(refreshEspAll)
        pcall(function()
            serverPlayersText:SetText("Players: " .. tostring(#Players:GetPlayers()))
        end)
        if state.selected and not state.selected.Parent then
            state.selected = nil
            updateActions()
        end
    end
end))

-- Player events ------------------------------------------------------------

track(Players.PlayerAdded:Connect(function(player)
    if not active then
        return
    end
    task.defer(render)
    track(player.CharacterAdded:Connect(function()
        task.wait(0.2)
        if active then
            pcall(refreshEspPlayer, player)
        end
    end))
end))

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        track(player.CharacterAdded:Connect(function()
            task.wait(0.2)
            if active then
                pcall(refreshEspPlayer, player)
            end
        end))
    end
end

track(Players.PlayerRemoving:Connect(function(player)
    clearEspEntry(player)
    if state.spectating == player then
        stopSpectate(true)
    end
    if state.selected == player then
        state.selected = nil
        updateActions()
    end
    task.defer(render)
end))

track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if not active then
        return
    end
    applySpeed()
    applyJump()
    if state.frozen then
        local root = getRoot(LocalPlayer)
        if root then
            pcall(function()
                root.Anchored = true
            end)
        end
    end
    if state.fly then
        local respawnRoot = getRoot(LocalPlayer)
        flyPosition = respawnRoot and respawnRoot.Position or nil
    end
    if state.fly or state.ragdoll then
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid then
            pcall(function()
                humanoid.PlatformStand = true
            end)
        end
    end
    if state.spin then
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid then
            pcall(function()
                humanoid.AutoRotate = false
            end)
        end
    end
end))

-- Anti-AFK -----------------------------------------------------------------

track(LocalPlayer.Idled:Connect(function()
    if not state.antiAfk then
        return
    end
    local ok = pcall(function()
        local virtualUser = game:GetService("VirtualUser")
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new())
    end)
    if not ok then
        state.antiAfk = false
        syncToggle("anti_afk", false)
        notify("Anti-AFK is not supported by this executor.")
    end
end))

-- Startup ------------------------------------------------------------------

render()
updateActions()

env.TokyoMultitoolCleanup = function()
    cleanup(true)
end
