--[[
    Avatar Copier — v1.0.0
    ----------------------
    A fully client-side Roblox avatar copier for Delta Executor.

    What it does:
      * Reads a Roblox avatar (by username, user ID, or profile URL) and applies
        its HumanoidDescription to YOUR OWN character.
      * The change is applied locally only. Roblox does not replicate character
        appearance changes made from the client, so other players keep seeing
        your normal avatar. Nothing is sent to the game server.

    What it does NOT do:
      * It does not modify other players, the game, or any server state.
      * It does not bypass any game system or grant any advantage.
      * It does not upload, collect, or transmit your data anywhere.

    Usage:
        Paste this file into Delta Executor and execute it, or:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/ArchDityaa/avatar-copier/main/src/CopyAvatar.lua"))()

    License: MIT — see LICENSE. Read DISCLAIMER.md before use.
]]

local CONFIG = {
    VERSION = "1.0.0",
    ACCENT = Color3.fromRGB(99, 102, 241),
    ACCENT_HOVER = Color3.fromRGB(129, 140, 248),
    COPY_COOLDOWN = 1.5, -- seconds; keeps the avatar API from rate-limiting you
    START_POSITION = UDim2.fromOffset(60, 100),
}

local COLORS = {
    background = Color3.fromRGB(24, 24, 27),
    surface = Color3.fromRGB(39, 39, 46),
    surfaceHover = Color3.fromRGB(52, 52, 61),
    stroke = Color3.fromRGB(63, 63, 70),
    text = Color3.fromRGB(244, 244, 245),
    textMuted = Color3.fromRGB(161, 161, 170),
    success = Color3.fromRGB(74, 222, 128),
    error = Color3.fromRGB(248, 113, 113),
    warning = Color3.fromRGB(250, 204, 21),
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return warn("[Avatar Copier] No LocalPlayer; run this script inside Roblox.")
end

local LOG_PREFIX = "[Avatar Copier]"

-- ---------------------------------------------------------------- state

local busy = false
local lastCopyAt = 0
local originalDescription = nil
local destroyed = false

local screenGui
local statusLabel
local inputBox
local copyButton
local resetButton

-- ------------------------------------------------------------ utilities

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function makeLabel(parent, text, size, position, font, color, textSize)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = size
    label.Position = position
    label.Font = font
    label.Text = text
    label.TextColor3 = color
    label.TextSize = textSize
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function styleButton(button, baseColor, hoverColor)
    button.AutoButtonColor = false
    button.BackgroundColor3 = baseColor

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = hoverColor }):Play()
    end)
    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = baseColor }):Play()
    end)
end

local function setStatus(message, color)
    if destroyed or not statusLabel then
        return
    end
    statusLabel.Text = message
    statusLabel.TextColor3 = color or COLORS.textMuted
end

-- ------------------------------------------------------------ GUI

local connections = {}

local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function getGuiParent()
    if type(gethui) == "function" then
        local ok, container = pcall(gethui)
        if ok and container then
            return container
        end
    end

    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and coreGui then
        return coreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function buildInterface()
    local parent = getGuiParent()

    local previous = parent:FindFirstChild("AvatarCopierGui")
    if previous then
        previous:Destroy()
    end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AvatarCopierGui"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 9999
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local window = Instance.new("Frame")
    window.Name = "Window"
    window.Size = UDim2.fromOffset(300, 196)
    window.Position = CONFIG.START_POSITION
    window.BackgroundColor3 = COLORS.background
    window.BorderSizePixel = 0

    makeCorner(window, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.stroke
    stroke.Thickness = 1
    stroke.Parent = window

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 34)
    titleBar.BackgroundColor3 = COLORS.surface
    titleBar.BorderSizePixel = 0
    titleBar.Parent = window
    makeCorner(titleBar, 12)

    local titleFill = Instance.new("Frame")
    titleFill.Size = UDim2.new(1, 0, 0, 12)
    titleFill.Position = UDim2.new(0, 0, 1, -12)
    titleFill.BackgroundColor3 = COLORS.surface
    titleFill.BorderSizePixel = 0
    titleFill.Parent = titleBar

    makeLabel(
        titleBar,
        "Avatar Copier",
        UDim2.new(1, -90, 1, 0),
        UDim2.fromOffset(12, 0),
        Enum.Font.GothamBold,
        COLORS.text,
        14
    )

    makeLabel(
        titleBar,
        "v" .. CONFIG.VERSION,
        UDim2.fromOffset(48, 34),
        UDim2.new(1, -80, 0, 0),
        Enum.Font.Gotham,
        COLORS.textMuted,
        11
    )

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "Close"
    closeButton.Size = UDim2.fromOffset(24, 24)
    closeButton.Position = UDim2.new(1, -32, 0, 5)
    closeButton.BackgroundColor3 = COLORS.surface
    closeButton.BorderSizePixel = 0
    closeButton.Text = "×"
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 16
    closeButton.TextColor3 = COLORS.textMuted
    closeButton.Parent = titleBar
    makeCorner(closeButton, 6)
    styleButton(closeButton, COLORS.surface, COLORS.surfaceHover)

    inputBox = Instance.new("TextBox")
    inputBox.Name = "TargetInput"
    inputBox.Size = UDim2.new(1, -24, 0, 36)
    inputBox.Position = UDim2.fromOffset(12, 44)
    inputBox.BackgroundColor3 = COLORS.surface
    inputBox.BorderSizePixel = 0
    inputBox.Font = Enum.Font.Gotham
    inputBox.TextSize = 13
    inputBox.TextColor3 = COLORS.text
    inputBox.PlaceholderText = "Username, user ID, or profile URL"
    inputBox.PlaceholderColor3 = COLORS.textMuted
    inputBox.Text = ""
    inputBox.ClearTextOnFocus = true
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.Parent = window
    makeCorner(inputBox, 8)

    local inputPadding = Instance.new("UIPadding")
    inputPadding.PaddingLeft = UDim.new(0, 10)
    inputPadding.PaddingRight = UDim.new(0, 10)
    inputPadding.Parent = inputBox

    copyButton = Instance.new("TextButton")
    copyButton.Name = "Copy"
    copyButton.Size = UDim2.fromOffset(184, 34)
    copyButton.Position = UDim2.fromOffset(12, 88)
    copyButton.BorderSizePixel = 0
    copyButton.Font = Enum.Font.GothamBold
    copyButton.TextSize = 13
    copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyButton.Text = "Copy"
    copyButton.Parent = window
    makeCorner(copyButton, 8)
    styleButton(copyButton, CONFIG.ACCENT, CONFIG.ACCENT_HOVER)

    resetButton = Instance.new("TextButton")
    resetButton.Name = "Reset"
    resetButton.Size = UDim2.fromOffset(84, 34)
    resetButton.Position = UDim2.fromOffset(204, 88)
    resetButton.BorderSizePixel = 0
    resetButton.Font = Enum.Font.GothamMedium
    resetButton.TextSize = 13
    resetButton.TextColor3 = COLORS.text
    resetButton.Text = "Reset"
    resetButton.Parent = window
    makeCorner(resetButton, 8)
    styleButton(resetButton, COLORS.surface, COLORS.surfaceHover)

    statusLabel = makeLabel(
        window,
        "Enter a username to begin.",
        UDim2.new(1, -24, 0, 28),
        UDim2.fromOffset(12, 130),
        Enum.Font.Gotham,
        COLORS.textMuted,
        11
    )
    statusLabel.TextWrapped = true
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top

    local footer = makeLabel(
        window,
        "Local preview only — other players can't see it.",
        UDim2.new(1, -24, 0, 14),
        UDim2.fromOffset(12, 164),
        Enum.Font.Gotham,
        COLORS.textMuted,
        10
    )
    footer.TextTransparency = 0.25

    screenGui.Parent = parent

    -- dragging -------------------------------------------------------

    local dragging = false
    local dragStart
    local startPosition

    track(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = window.AbsolutePosition
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local delta = input.Position - dragStart

        local x = math.clamp(
            startPosition.X + delta.X,
            0,
            math.max(0, viewport.X - window.AbsoluteSize.X)
        )
        local y = math.clamp(
            startPosition.Y + delta.Y,
            0,
            math.max(0, viewport.Y - window.AbsoluteSize.Y)
        )
        window.Position = UDim2.fromOffset(x, y)
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    -- lifecycle ------------------------------------------------------

    local function destroy()
        if destroyed then
            return
        end
        destroyed = true
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        screenGui:Destroy()
        if type(getgenv) == "function" and getgenv().AvatarCopier then
            getgenv().AvatarCopier = nil
        end
    end

    track(closeButton.MouseButton1Click:Connect(destroy))

    return destroy
end

-- ------------------------------------------------------ avatar pipeline

local function findServerPlayer(query)
    local lowered = query:lower()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower() == lowered or player.DisplayName:lower() == lowered then
            return player
        end
    end
    return nil
end

local function readPlayerDescription(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil
    end

    local ok, description = pcall(function()
        return humanoid:GetAppliedDescription()
    end)
    if ok and typeof(description) == "Instance" and description:IsA("HumanoidDescription") then
        return description
    end
    return nil
end

local function parseTarget(raw)
    if type(raw) ~= "string" then
        return nil, nil
    end

    local trimmed = raw:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil, nil
    end

    -- Accept https://www.roblox.com/users/1234567/profile
    local fromUrl = trimmed:match("users/(%d+)")
    if fromUrl then
        return "id", tonumber(fromUrl)
    end

    -- Accept a raw numeric ID
    if trimmed:match("^%d+$") then
        local id = tonumber(trimmed)
        if id and id > 0 then
            return "id", id
        end
    end

    -- Accept a leading "@" from mentions
    trimmed = trimmed:gsub("^@", "")
    if trimmed == "" then
        return nil, nil
    end

    return "name", trimmed
end

local function resolveDescription(kind, value)
    if kind == "name" then
        -- Fast path: name matches someone already in this server.
        local serverPlayer = findServerPlayer(value)
        if serverPlayer then
            local description = readPlayerDescription(serverPlayer)
            if description then
                return description, "server", serverPlayer.Name
            end
        end

        local ok, userId = pcall(function()
            return Players:GetUserIdFromNameAsync(value)
        end)
        if not ok or type(userId) ~= "number" or userId <= 0 then
            return nil, "not_found"
        end
        value = userId
    end

    local ok, description = pcall(function()
        return Players:GetHumanoidDescriptionFromUserIdAsync(value)
    end)
    if ok and typeof(description) == "Instance" and description:IsA("HumanoidDescription") then
        return description, "avatar_api"
    end

    return nil, "fetch_failed"
end

local function getLocalHumanoid()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        local deadline = os.clock() + 8
        repeat
            task.wait(0.1)
            character = LocalPlayer.Character
        until (character and character.Parent) or os.clock() > deadline
    end

    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        local deadline = os.clock() + 5
        repeat
            task.wait(0.1)
            humanoid = character:FindFirstChildOfClass("Humanoid")
        until humanoid or os.clock() > deadline
    end

    return humanoid
end

-- Newer Clients use the *Async variants; fall back for older ones.
local APPLY_ATTEMPTS = {
    {
        name = "ApplyDescriptionAsync",
        call = function(humanoid, description)
            return humanoid:ApplyDescriptionAsync(description, Enum.AssetTypeVerification.Default)
        end,
    },
    {
        name = "ApplyDescriptionResetAsync",
        call = function(humanoid, description)
            return humanoid:ApplyDescriptionResetAsync(description, Enum.AssetTypeVerification.Default)
        end,
    },
    {
        name = "ApplyDescription",
        call = function(humanoid, description)
            return humanoid:ApplyDescription(description, Enum.AssetTypeVerification.Default)
        end,
    },
    {
        name = "ApplyDescriptionReset",
        call = function(humanoid, description)
            return humanoid:ApplyDescriptionReset(description, Enum.AssetTypeVerification.Default)
        end,
    },
}

local function applyLocally(humanoid, description)
    if not (typeof(description) == "Instance" and description:IsA("HumanoidDescription")) then
        return false, "Invalid HumanoidDescription"
    end

    local errors = {}
    for _, attempt in ipairs(APPLY_ATTEMPTS) do
        if type(humanoid[attempt.name]) == "function" then
            local ok, err = pcall(attempt.call, humanoid, description)
            if ok then
                return true, attempt.name
            end
            table.insert(errors, attempt.name .. ": " .. tostring(err))
        end
    end

    return false, table.concat(errors, " | ")
end

local function copyAvatar(rawTarget)
    if destroyed then
        return false, "Interface is closed."
    end
    if busy then
        return false, "A copy is already in progress."
    end
    if os.clock() - lastCopyAt < CONFIG.COPY_COOLDOWN then
        return false, "Please wait a moment before trying again."
    end

    local kind, value = parseTarget(rawTarget)
    if not kind then
        setStatus("Enter a username or user ID first.", COLORS.error)
        return false, "Empty input."
    end

    local displayTarget = tostring(value)

    busy = true
    if copyButton then
        copyButton.Text = "Working…"
    end
    setStatus("Resolving avatar…", COLORS.warning)

    local description, source, resolvedName = resolveDescription(kind, value)

    if destroyed then
        busy = false
        return false, "Interface is closed."
    end

    if not description then
        busy = false
        if copyButton then
            copyButton.Text = "Copy"
        end

        if source == "not_found" then
            setStatus("Player not found. Check the spelling.", COLORS.error)
            return false, "Player not found."
        end

        setStatus("Could not load that avatar (invalid ID, private, or rate-limited).", COLORS.error)
        return false, "Avatar fetch failed."
    end

    local label = resolvedName or displayTarget

    local humanoid = getLocalHumanoid()
    if not humanoid then
        busy = false
        if copyButton then
            copyButton.Text = "Copy"
        end
        setStatus("Your character is not ready yet.", COLORS.error)
        return false, "Character not ready."
    end

    -- Snapshot the player's original look once, for the Reset button.
    if not originalDescription then
        local ok, snapshot = pcall(function()
            return humanoid:GetAppliedDescription()
        end)
        if ok then
            originalDescription = snapshot
        end
    end

    setStatus("Applying avatar locally…", COLORS.warning)
    local ok, detail = applyLocally(humanoid, description)

    busy = false
    if copyButton then
        copyButton.Text = "Copy"
    end

    if ok then
        lastCopyAt = os.clock()
        setStatus(("Copied from %s (local only)"):format(label), COLORS.success)
        return true, "Avatar applied via " .. tostring(detail)
    end

    warn(("%s Failed to apply description: %s"):format(LOG_PREFIX, tostring(detail)))
    setStatus("Failed to apply. Try another avatar or rejoin.", COLORS.error)
    return false, "Apply failed."
end

local function resetAvatar()
    if destroyed then
        return false, "Interface is closed."
    end

    local humanoid = getLocalHumanoid()
    if not humanoid then
        setStatus("Your character is not ready yet.", COLORS.error)
        return false, "Character not ready."
    end

    if originalDescription then
        local ok = applyLocally(humanoid, originalDescription)
        if ok then
            setStatus("Restored your own avatar.", COLORS.success)
            return true, "Original avatar restored."
        end
    end

    local ok = pcall(function()
        LocalPlayer:ClearCharacterAppearance()
    end)
    if ok then
        setStatus("Restored your own avatar.", COLORS.success)
        return true, "Appearance cleared."
    end

    setStatus("Could not restore your avatar.", COLORS.error)
    return false, "Reset failed."
end

-- ------------------------------------------------------------- startup

local destroyInterface = buildInterface()

track(copyButton.MouseButton1Click:Connect(function()
    task.spawn(function()
        copyAvatar(inputBox.Text)
    end)
end))

track(resetButton.MouseButton1Click:Connect(function()
    task.spawn(resetAvatar)
end))

track(inputBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        task.spawn(function()
            copyAvatar(inputBox.Text)
        end)
    end
end))

-- Programmatic API for power users:
--   AvatarCopier.copy("Roblox")   AvatarCopier.reset()   AvatarCopier.destroy()
if type(getgenv) == "function" then
    getgenv().AvatarCopier = {
        version = CONFIG.VERSION,
        copy = function(target)
            task.spawn(copyAvatar, target)
        end,
        reset = function()
            task.spawn(resetAvatar)
        end,
        destroy = destroyInterface,
    }
end

print(("%s v%s loaded. Client-side only."):format(LOG_PREFIX, CONFIG.VERSION))
