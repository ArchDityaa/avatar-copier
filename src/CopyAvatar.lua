--[[
    Avatar Copier — v1.2.0
    ----------------------
    A fully client-side Roblox avatar copier for Delta Executor.

    What it does:
      * Reads a Roblox avatar (by username, user ID, or profile URL) and applies
        its HumanoidDescription to YOUR OWN character.
      * The change is applied locally only. Roblox does not replicate character
        appearance changes made from the client, so other players keep seeing
        your normal avatar. Nothing is sent to the game server.
      * Copies unexpected script errors to the executor clipboard, together with
        the version, context, and traceback, so bug reports are easy to paste.

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
    VERSION = "1.2.0",
    ACCENT = Color3.fromRGB(99, 102, 241),
    ACCENT_HOVER = Color3.fromRGB(129, 140, 248),
    ACCENT_PRESSED = Color3.fromRGB(79, 70, 229),
    COPY_COOLDOWN = 1.5, -- seconds; keeps the avatar API from rate-limiting you
    WINDOW_WIDTH = 320,
    WINDOW_HEIGHT = 272,
    MIN_SCALE = 0.8,
    START_POSITION = UDim2.fromOffset(60, 100),
    MOBILE_POSITION = UDim2.fromOffset(16, 64),
}

local COLORS = {
    background = Color3.fromRGB(24, 24, 27),
    surface = Color3.fromRGB(35, 35, 41),
    surfaceAlt = Color3.fromRGB(42, 42, 50),
    surfaceHover = Color3.fromRGB(52, 52, 61),
    stroke = Color3.fromRGB(63, 63, 70),
    strokeSoft = Color3.fromRGB(45, 45, 52),
    text = Color3.fromRGB(244, 244, 245),
    textMuted = Color3.fromRGB(161, 161, 170),
    success = Color3.fromRGB(74, 222, 128),
    error = Color3.fromRGB(248, 113, 113),
    warning = Color3.fromRGB(250, 204, 21),
}

local STATUS_THEMES = {
    idle = {
        dot = COLORS.textMuted,
        background = COLORS.surface,
        text = COLORS.textMuted,
    },
    loading = {
        dot = COLORS.warning,
        background = Color3.fromRGB(45, 40, 26),
        text = COLORS.warning,
    },
    success = {
        dot = COLORS.success,
        background = Color3.fromRGB(26, 48, 37),
        text = COLORS.success,
    },
    warning = {
        dot = COLORS.warning,
        background = Color3.fromRGB(48, 42, 24),
        text = COLORS.warning,
    },
    error = {
        dot = COLORS.error,
        background = Color3.fromRGB(52, 31, 33),
        text = COLORS.error,
    },
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return warn("[Avatar Copier] No LocalPlayer; run this script inside Roblox.")
end

local LOG_PREFIX = "[Avatar Copier]"

-- ------------------------------------------------------- error reporting

-- Unexpected errors are copied to the executor clipboard so users can paste a
-- complete report when asking for help. All clipboard work is protected: a
-- missing or broken clipboard API must never hide the original error.
local MAX_CLIPBOARD_LENGTH = 8000
local CLIPBOARD_FUNCTIONS = { "setclipboard", "toclipboard", "writeclipboard" }
local CLIPBOARD_GLOBALS = {
    setclipboard = function()
        return setclipboard
    end,
    toclipboard = function()
        return toclipboard
    end,
    writeclipboard = function()
        return writeclipboard
    end,
}

local function resolveClipboard()
    local env
    if type(getgenv) == "function" then
        local ok, result = pcall(getgenv)
        if ok and type(result) == "table" then
            env = result
        end
    end

    for _, name in ipairs(CLIPBOARD_FUNCTIONS) do
        if env and type(env[name]) == "function" then
            return env[name], name
        end

        local getter = CLIPBOARD_GLOBALS[name]
        local ok, fn = pcall(getter)
        if ok and type(fn) == "function" then
            return fn, name
        end
    end

    return nil, "setclipboard, toclipboard, or writeclipboard is unavailable"
end

local function safeToString(value)
    local ok, text = pcall(tostring, value)
    if ok then
        return text
    end
    return "<unprintable value>"
end

local function copyToClipboard(text)
    local setter, name = resolveClipboard()
    if not setter then
        return false, name
    end

    local ok, err = pcall(setter, text)
    if ok then
        return true, name
    end

    return false, ("%s failed: %s"):format(name, safeToString(err))
end

local function reportError(context, err)
    local message = safeToString(err)
    local contextText = safeToString(context)
    local traceback = message

    local traceOk, captured = pcall(function()
        return debug.traceback(message, 2)
    end)
    if traceOk and type(captured) == "string" and captured ~= "" then
        traceback = captured
    end

    local timestamp = "unknown time"
    local timeOk, timeText = pcall(function()
        return os.date("!%Y-%m-%d %H:%M:%S") .. " UTC"
    end)
    if timeOk and type(timeText) == "string" and timeText ~= "" then
        timestamp = timeText
    end

    local report = table.concat({
        ("Avatar Copier v%s - error report"):format(CONFIG.VERSION),
        "Time: " .. timestamp,
        "Context: " .. contextText,
        "Error: " .. message,
        "Traceback:",
        traceback,
    }, "\n")

    if #report > MAX_CLIPBOARD_LENGTH then
        report = report:sub(1, MAX_CLIPBOARD_LENGTH) .. "\n...[truncated]"
    end

    pcall(warn, ("%s Unexpected error (%s): %s"):format(LOG_PREFIX, contextText, message))

    local copied, method = copyToClipboard(report)
    if copied then
        pcall(print, ("%s Error report copied to the clipboard via %s."):format(LOG_PREFIX, safeToString(method)))
    else
        pcall(warn, ("%s Could not copy the error report to the clipboard (%s)."):format(
            LOG_PREFIX,
            safeToString(method)
        ))
    end

    return report
end

local function safeCall(context, callback, ...)
    local args = { ... }
    local count = select("#", ...)

    return xpcall(function()
        return callback(table.unpack(args, 1, count))
    end, function(err)
        return reportError(context, err)
    end)
end

-- ---------------------------------------------------------------- state

local busy = false
local lastCopyAt = -math.huge
local originalDescription = nil
local destroyed = false

local screenGui
local window
local uiScale
local statusCard
local statusDot
local statusText
local inputBox
local copyButton
local resetButton
local clearButton

-- ------------------------------------------------------------ utilities

local connections = {}

local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function makeStroke(parent, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness or 1
    stroke.Parent = parent
    return stroke
end

local function makeLabel(parent, text, size, position, font, color, textSize, name)
    local label = Instance.new("TextLabel")
    if name then
        label.Name = name
    end
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

local function makeButton(parent, name, text, size, position, font, textSize, textColor, baseColor)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = size
    button.Position = position
    button.BackgroundColor3 = baseColor
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Active = true
    button.Text = text
    button.Font = font
    button.TextSize = textSize
    button.TextColor3 = textColor
    button.Parent = parent
    makeCorner(button, 9)
    return button
end

local function styleButton(button, baseColor, hoverColor)
    button.BackgroundColor3 = baseColor

    track(button.MouseEnter:Connect(function()
        safeCall("button hover", function()
            if button.Active == false then
                return
            end
            TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = hoverColor }):Play()
        end)
    end))

    track(button.MouseLeave:Connect(function()
        safeCall("button unhover", function()
            if button.Active == false then
                return
            end
            TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = baseColor }):Play()
        end)
    end))
end

local function setStatus(message, state)
    if destroyed or not statusText then
        return
    end

    local theme = STATUS_THEMES[state or "idle"] or STATUS_THEMES.idle
    statusText.Text = message
    statusText.TextColor3 = theme.text

    if statusDot then
        statusDot.BackgroundColor3 = theme.dot
    end

    if statusCard then
        TweenService:Create(
            statusCard,
            TweenInfo.new(0.15),
            { BackgroundColor3 = theme.background }
        ):Play()
    end
end

local function setControlsEnabled(enabled)
    if copyButton then
        copyButton.Active = enabled
        copyButton.BackgroundColor3 = enabled and CONFIG.ACCENT or CONFIG.ACCENT_PRESSED
    end

    if resetButton then
        resetButton.Active = enabled
        resetButton.BackgroundColor3 = enabled and COLORS.surface or COLORS.surfaceAlt
    end

    if clearButton then
        clearButton.Active = enabled
    end
end

local function setBusy(value)
    busy = value

    if copyButton then
        copyButton.Text = value and "Copying..." or "Copy avatar"
    end

    setControlsEnabled(not value)
end

local function runSafely(context, callback, ...)
    local args = { ... }
    local count = select("#", ...)

    task.spawn(function()
        local ok = safeCall(context, callback, table.unpack(args, 1, count))
        if not ok then
            pcall(setBusy, false)
            pcall(setStatus, "Unexpected error. Details copied to clipboard.", "error")
        end
    end)
end

local function refreshClearButton()
    if clearButton and inputBox then
        clearButton.Visible = inputBox.Text ~= ""
    end
end

local function updateScale()
    if not uiScale then
        return
    end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local availableX = math.max(1, viewport.X - 24)
    local availableY = math.max(1, viewport.Y - 24)
    local scale = math.min(1, availableX / CONFIG.WINDOW_WIDTH, availableY / CONFIG.WINDOW_HEIGHT)

    uiScale.Scale = math.clamp(scale, CONFIG.MIN_SCALE, 1)
end

-- ------------------------------------------------------------ GUI

local function getPlayerGui()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        return playerGui
    end

    local ok, result = pcall(function()
        return LocalPlayer:WaitForChild("PlayerGui", 5)
    end)
    if ok then
        return result
    end

    return nil
end

local function candidateParents()
    local candidates = {}
    local seen = {}

    local function add(name, instance)
        if type(typeof) == "function" and typeof(instance) ~= "Instance" then
            return
        end
        if not instance or seen[instance] then
            return
        end

        seen[instance] = true
        table.insert(candidates, { name = name, instance = instance })
    end

    local playerGui = getPlayerGui()

    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if not ok then
        coreGui = nil
    end

    local hui = nil
    if type(gethui) == "function" then
        local huiOk, container = pcall(gethui)
        if huiOk then
            hui = container
        end
    end

    local override = nil
    if type(getgenv) == "function" then
        local env = getgenv()
        if type(env) == "table" then
            override = env.AVATAR_COPIER_PARENT
        end
    end

    -- Some mobile executors hide gethui containers; PlayerGui is the safer default there.
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

    local order
    if isMobile then
        order = { "PlayerGui", "gethui", "CoreGui" }
    else
        order = { "gethui", "CoreGui", "PlayerGui" }
    end

    if type(override) == "string" then
        local normalized = string.lower(override)
        local reordered = { normalized }
        for _, name in ipairs(order) do
            if string.lower(name) ~= normalized then
                table.insert(reordered, string.lower(name))
            end
        end
        order = reordered
    end

    local byName = {
        playergui = playerGui,
        coregui = coreGui,
        gethui = hui,
    }

    local displayNames = {
        playergui = "PlayerGui",
        coregui = "CoreGui",
        gethui = "gethui",
    }

    for _, key in ipairs(order) do
        local normalized = string.lower(key)
        add(displayNames[normalized] or key, byName[normalized])
    end

    return candidates
end

local function attachGui(gui)
    local failures = {}

    for _, candidate in ipairs(candidateParents()) do
        gui.Parent = nil

        local ok, err = pcall(function()
            gui.Parent = candidate.instance
        end)

        if ok and gui.Parent == candidate.instance and gui:IsDescendantOf(game) then
            return candidate.name
        end

        table.insert(
            failures,
            ("%s: %s"):format(candidate.name, tostring(err or "rejected or detached"))
        )
    end

    if #failures == 0 then
        return nil, "no candidate parents available"
    end

    return nil, table.concat(failures, "; ")
end

local function removePreviousGuis()
    for _, candidate in ipairs(candidateParents()) do
        local ok, previous = pcall(function()
            return candidate.instance:FindFirstChild("AvatarCopierGui")
        end)
        if ok and previous then
            pcall(function()
                previous:Destroy()
            end)
        end
    end
end

local function buildHeader(titleBar)
    local logo = Instance.new("Frame")
    logo.Name = "Logo"
    logo.Size = UDim2.fromOffset(26, 26)
    logo.Position = UDim2.fromOffset(14, 9)
    logo.BackgroundColor3 = CONFIG.ACCENT
    logo.BorderSizePixel = 0
    logo.Parent = titleBar
    makeCorner(logo, 8)

    local mark = makeLabel(
        logo,
        "A",
        UDim2.fromScale(1, 1),
        UDim2.fromScale(0, 0),
        Enum.Font.GothamBlack,
        Color3.fromRGB(255, 255, 255),
        13,
        "Mark"
    )
    mark.TextXAlignment = Enum.TextXAlignment.Center
    mark.TextYAlignment = Enum.TextYAlignment.Center

    makeLabel(
        titleBar,
        "Avatar Copier",
        UDim2.new(1, -170, 1, 0),
        UDim2.fromOffset(50, 0),
        Enum.Font.GothamBold,
        COLORS.text,
        14,
        "Title"
    )

    local versionPill = Instance.new("Frame")
    versionPill.Name = "VersionPill"
    versionPill.Size = UDim2.fromOffset(54, 20)
    versionPill.Position = UDim2.new(1, -104, 0, 12)
    versionPill.BackgroundColor3 = COLORS.surfaceAlt
    versionPill.BorderSizePixel = 0
    versionPill.Parent = titleBar
    makeCorner(versionPill, 6)

    local versionText = makeLabel(
        versionPill,
        "v" .. CONFIG.VERSION,
        UDim2.fromScale(1, 1),
        UDim2.fromScale(0, 0),
        Enum.Font.Gotham,
        COLORS.textMuted,
        10,
        "Text"
    )
    versionText.TextXAlignment = Enum.TextXAlignment.Center
    versionText.TextYAlignment = Enum.TextYAlignment.Center

    local closeButton = makeButton(
        titleBar,
        "Close",
        "×",
        UDim2.fromOffset(32, 32),
        UDim2.new(1, -42, 0, 6),
        Enum.Font.GothamBold,
        18,
        COLORS.textMuted,
        COLORS.surfaceAlt
    )
    styleButton(closeButton, COLORS.surfaceAlt, COLORS.surfaceHover)

    return closeButton
end

local function buildSearchIcon(parent, position)
    local icon = Instance.new("Frame")
    icon.Name = "SearchIcon"
    icon.Size = UDim2.fromOffset(16, 16)
    icon.Position = position
    icon.BackgroundTransparency = 1
    icon.Parent = parent

    local lens = Instance.new("Frame")
    lens.Name = "Lens"
    lens.Size = UDim2.fromOffset(9, 9)
    lens.Position = UDim2.fromOffset(1, 1)
    lens.BackgroundTransparency = 1
    lens.Parent = icon
    makeCorner(lens, 99)
    makeStroke(lens, COLORS.textMuted, 1.5)

    local handle = Instance.new("Frame")
    handle.Name = "Handle"
    handle.Size = UDim2.fromOffset(6, 2)
    handle.Position = UDim2.fromOffset(9, 10)
    handle.BackgroundColor3 = COLORS.textMuted
    handle.BorderSizePixel = 0
    handle.Rotation = 45
    handle.Parent = icon
    makeCorner(handle, 1)
end

local function buildBody(parent)
    makeLabel(
        parent,
        "TARGET PLAYER",
        UDim2.fromOffset(200, 12),
        UDim2.fromOffset(14, 58),
        Enum.Font.GothamBold,
        COLORS.textMuted,
        10,
        "TargetLabel"
    )

    inputBox = Instance.new("TextBox")
    inputBox.Name = "TargetInput"
    inputBox.Size = UDim2.new(1, -28, 0, 40)
    inputBox.Position = UDim2.fromOffset(14, 74)
    inputBox.BackgroundColor3 = COLORS.surface
    inputBox.BorderSizePixel = 0
    inputBox.Font = Enum.Font.Gotham
    inputBox.TextSize = 13
    inputBox.TextColor3 = COLORS.text
    inputBox.PlaceholderText = "Username, user ID, or profile URL"
    inputBox.PlaceholderColor3 = COLORS.textMuted
    inputBox.Text = ""
    inputBox.ClearTextOnFocus = false
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.Parent = parent
    makeCorner(inputBox, 10)
    local inputStroke = makeStroke(inputBox, COLORS.stroke, 1)

    track(inputBox.Focused:Connect(function()
        safeCall("input focus", function()
            inputStroke.Color = CONFIG.ACCENT
        end)
    end))

    track(inputBox.FocusLost:Connect(function()
        safeCall("input blur", function()
            inputStroke.Color = COLORS.stroke
        end)
    end))

    local inputPadding = Instance.new("UIPadding")
    inputPadding.PaddingLeft = UDim.new(0, 34)
    inputPadding.PaddingRight = UDim.new(0, 34)
    inputPadding.Parent = inputBox

    -- Icons are siblings of the TextBox: UIPadding would also offset children.
    buildSearchIcon(parent, UDim2.fromOffset(26, 86))

    clearButton = makeButton(
        parent,
        "Clear",
        "×",
        UDim2.fromOffset(24, 24),
        UDim2.fromOffset(276, 82),
        Enum.Font.GothamBold,
        14,
        COLORS.textMuted,
        COLORS.surfaceAlt
    )
    clearButton.Visible = false
    styleButton(clearButton, COLORS.surfaceAlt, COLORS.surfaceHover)

    makeLabel(
        parent,
        "Username, user ID, or profile URL",
        UDim2.new(1, -28, 0, 12),
        UDim2.fromOffset(14, 118),
        Enum.Font.Gotham,
        COLORS.textMuted,
        10,
        "Helper"
    )

    copyButton = makeButton(
        parent,
        "Copy",
        "Copy avatar",
        UDim2.fromOffset(196, 40),
        UDim2.fromOffset(14, 138),
        Enum.Font.GothamBold,
        13,
        Color3.fromRGB(255, 255, 255),
        CONFIG.ACCENT
    )
    styleButton(copyButton, CONFIG.ACCENT, CONFIG.ACCENT_HOVER)

    resetButton = makeButton(
        parent,
        "Reset",
        "Reset",
        UDim2.fromOffset(88, 40),
        UDim2.fromOffset(218, 138),
        Enum.Font.GothamMedium,
        13,
        COLORS.text,
        COLORS.surface
    )
    makeStroke(resetButton, COLORS.stroke, 1)
    styleButton(resetButton, COLORS.surface, COLORS.surfaceHover)

    statusCard = Instance.new("Frame")
    statusCard.Name = "StatusCard"
    statusCard.Size = UDim2.new(1, -28, 0, 48)
    statusCard.Position = UDim2.fromOffset(14, 190)
    statusCard.BackgroundColor3 = COLORS.surface
    statusCard.BorderSizePixel = 0
    statusCard.Parent = parent
    makeCorner(statusCard, 10)
    makeStroke(statusCard, COLORS.strokeSoft, 1)

    statusDot = Instance.new("Frame")
    statusDot.Name = "Dot"
    statusDot.Size = UDim2.fromOffset(6, 6)
    statusDot.Position = UDim2.fromOffset(12, 21)
    statusDot.BackgroundColor3 = COLORS.textMuted
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusCard
    makeCorner(statusDot, 99)

    statusText = makeLabel(
        statusCard,
        "Enter a username to begin.",
        UDim2.new(1, -38, 1, 0),
        UDim2.fromOffset(26, 0),
        Enum.Font.Gotham,
        COLORS.textMuted,
        11,
        "StatusText"
    )
    statusText.TextWrapped = true
    statusText.TextYAlignment = Enum.TextYAlignment.Center

    local footer = makeLabel(
        parent,
        "Client-side only — other players can't see it.",
        UDim2.new(1, -28, 0, 14),
        UDim2.fromOffset(14, 248),
        Enum.Font.Gotham,
        COLORS.textMuted,
        10,
        "Footer"
    )
    footer.TextTransparency = 0.15
end

local function buildInterface()
    removePreviousGuis()

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AvatarCopierGui"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 9999
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = true

    local parentName, parentError = attachGui(screenGui)
    if not parentName then
        warn(("%s Could not attach the GUI (%s)."):format(LOG_PREFIX, tostring(parentError)))
        if screenGui then
            screenGui:Destroy()
            screenGui = nil
        end
        return nil
    end

    print(("%s GUI attached to %s."):format(LOG_PREFIX, parentName))

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local startPosition = isMobile and CONFIG.MOBILE_POSITION or CONFIG.START_POSITION

    window = Instance.new("Frame")
    window.Name = "Window"
    window.Size = UDim2.fromOffset(CONFIG.WINDOW_WIDTH, CONFIG.WINDOW_HEIGHT)
    window.Position = startPosition
    window.BackgroundColor3 = COLORS.background
    window.BorderSizePixel = 0
    window.Parent = screenGui
    makeCorner(window, 12)
    makeStroke(window, COLORS.stroke, 1)

    uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = window

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 44)
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

    local closeButton = buildHeader(titleBar)
    buildBody(window)
    updateScale()

    -- Responsive scale ------------------------------------------------

    local camera = workspace.CurrentCamera
    if camera then
        local ok, signal = pcall(function()
            return camera:GetPropertyChangedSignal("ViewportSize")
        end)
        if ok and signal then
            track(signal:Connect(function()
                safeCall("viewport resize", updateScale)
            end))
        end
    end

    -- dragging -------------------------------------------------------

    local dragging = false
    local dragStart
    local startPositionAbsolute

    track(titleBar.InputBegan:Connect(function(input)
        safeCall("drag start", function()
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPositionAbsolute = window.AbsolutePosition
            end
        end)
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        safeCall("drag move", function()
            if not dragging then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local currentCamera = workspace.CurrentCamera
            local viewport = currentCamera and currentCamera.ViewportSize or Vector2.new(1920, 1080)
            local delta = input.Position - dragStart

            local x = math.clamp(
                startPositionAbsolute.X + delta.X,
                0,
                math.max(0, viewport.X - window.AbsoluteSize.X)
            )
            local y = math.clamp(
                startPositionAbsolute.Y + delta.Y,
                0,
                math.max(0, viewport.Y - window.AbsoluteSize.Y)
            )
            window.Position = UDim2.fromOffset(x, y)
        end)
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        safeCall("drag end", function()
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
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
        if screenGui then
            screenGui:Destroy()
        end
        if type(getgenv) == "function" and getgenv().AvatarCopier then
            getgenv().AvatarCopier = nil
        end
    end

    track(closeButton.MouseButton1Click:Connect(function()
        safeCall("close button", destroy)
    end))

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
        setStatus("A copy is already in progress.", "warning")
        return false, "A copy is already in progress."
    end
    if os.clock() - lastCopyAt < CONFIG.COPY_COOLDOWN then
        setStatus("Please wait a moment before trying again.", "warning")
        return false, "Please wait a moment before trying again."
    end

    local kind, value = parseTarget(rawTarget)
    if not kind then
        setStatus("Enter a username or user ID first.", "error")
        return false, "Empty input."
    end

    local displayTarget = tostring(value)

    setBusy(true)
    setStatus("Resolving avatar...", "loading")

    local description, source, resolvedName = resolveDescription(kind, value)

    if destroyed then
        busy = false
        return false, "Interface is closed."
    end

    if not description then
        setBusy(false)

        if source == "not_found" then
            setStatus("Player not found. Check the spelling.", "error")
            return false, "Player not found."
        end

        setStatus("Could not load that avatar (invalid ID, private, or rate-limited).", "error")
        return false, "Avatar fetch failed."
    end

    local label = resolvedName or displayTarget

    local humanoid = getLocalHumanoid()
    if not humanoid then
        setBusy(false)
        setStatus("Your character is not ready yet.", "error")
        return false, "Character not ready."
    end

    if destroyed then
        busy = false
        return false, "Interface is closed."
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

    setStatus("Applying avatar locally...", "loading")
    local ok, detail = applyLocally(humanoid, description)

    setBusy(false)

    if ok then
        lastCopyAt = os.clock()
        setStatus(("Copied from %s (local only)"):format(label), "success")
        return true, "Avatar applied via " .. tostring(detail)
    end

    warn(("%s Failed to apply description: %s"):format(LOG_PREFIX, tostring(detail)))
    setStatus("Failed to apply. Try another avatar or rejoin.", "error")
    return false, "Apply failed."
end

local function resetAvatar()
    if destroyed then
        return false, "Interface is closed."
    end
    if busy then
        setStatus("Wait for the current copy to finish.", "warning")
        return false, "A copy is already in progress."
    end

    local humanoid = getLocalHumanoid()
    if not humanoid then
        setStatus("Your character is not ready yet.", "error")
        return false, "Character not ready."
    end

    if originalDescription then
        local ok = applyLocally(humanoid, originalDescription)
        if ok then
            setStatus("Restored your own avatar.", "success")
            return true, "Original avatar restored."
        end
    end

    local ok = pcall(function()
        LocalPlayer:ClearCharacterAppearance()
    end)
    if ok then
        setStatus("Restored your own avatar.", "success")
        return true, "Appearance cleared."
    end

    setStatus("Could not restore your avatar.", "error")
    return false, "Reset failed."
end

-- ------------------------------------------------------------- startup

local buildOk, buildResult = xpcall(buildInterface, function(err)
    return reportError("startup/build", err)
end)
if not buildOk then
    return
end

local destroyInterface = buildResult
if destroyInterface == nil then
    return
end

local function start()
    track(copyButton.MouseButton1Click:Connect(function()
        runSafely("copy button", copyAvatar, inputBox.Text)
    end))

    track(resetButton.MouseButton1Click:Connect(function()
        runSafely("reset button", resetAvatar)
    end))

    track(clearButton.MouseButton1Click:Connect(function()
        local ok = safeCall("clear button", function()
            inputBox.Text = ""
            refreshClearButton()
            setStatus("Enter a username to begin.", "idle")
            pcall(function()
                inputBox:CaptureFocus()
            end)
        end)
        if not ok then
            setStatus("Unexpected error. Details copied to clipboard.", "error")
        end
    end))

    track(inputBox.Changed:Connect(function(property)
        if property == "Text" then
            safeCall("input change", refreshClearButton)
        end
    end))

    track(inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            runSafely("enter key", copyAvatar, inputBox.Text)
        end
    end))

    -- Programmatic API for power users:
    --   AvatarCopier.copy("Roblox")   AvatarCopier.reset()   AvatarCopier.destroy()
    if type(getgenv) == "function" then
        getgenv().AvatarCopier = {
            version = CONFIG.VERSION,
            copy = function(target)
                runSafely("AvatarCopier.copy", copyAvatar, target)
            end,
            reset = function()
                runSafely("AvatarCopier.reset", resetAvatar)
            end,
            destroy = function()
                safeCall("AvatarCopier.destroy", destroyInterface)
            end,
        }
    end

    print(("%s v%s loaded. Client-side only."):format(LOG_PREFIX, CONFIG.VERSION))
end

local startOk = safeCall("startup", start)
if not startOk then
    pcall(setBusy, false)
    pcall(setStatus, "Startup failed. Details copied to clipboard.", "error")
end
