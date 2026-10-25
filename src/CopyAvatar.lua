--[[
    Avatar Copier — v1.4.0
    ----------------------
    A fully client-side Roblox avatar previewer for Delta Executor.

    What it does:
      * Reads a Roblox avatar (by username, user ID, or profile URL) and builds a
        client-only overlay model that looks like that avatar.
      * The overlay follows your character and mirrors its pose. Your real
        character is hidden locally, so only you see the preview. Nothing is sent
        to the game server and no server state is modified.
      * Copies unexpected errors and failed preview attempts to the executor
        clipboard, together with the version, context, target, and traceback, so
        bug reports are easy to paste.

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
    VERSION = "1.4.0",
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
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return warn("[Avatar Copier] No LocalPlayer; run this script inside Roblox.")
end

local LOG_PREFIX = "[Avatar Copier]"
local OVERLAY_FOLDER_NAME = "AvatarCopierOverlay"

-- If the script is executed again, let the previous instance disconnect its
-- connections and remove its overlay before this one starts. The GUI cleanup
-- below also runs, but connections and workspace models need explicit teardown.
local function cleanupPreviousInstance()
    if type(getgenv) ~= "function" then
        return
    end

    local ok, env = pcall(getgenv)
    if not ok or type(env) ~= "table" then
        return
    end

    local cleanup = env.AvatarCopierCleanup
    if type(cleanup) == "function" then
        pcall(cleanup)
    end
end

cleanupPreviousInstance()

-- ------------------------------------------------------- error reporting

-- Errors and failed preview attempts are copied to the executor clipboard so
-- users can paste a complete report when asking for help. All clipboard work is
-- protected: a missing or broken clipboard API must never hide the original
-- error, and the full report is printed to the console as a fallback.
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

    -- No usable clipboard function was exposed by this executor.
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

local function utcTimestamp()
    local ok, text = pcall(function()
        return os.date("!%Y-%m-%d %H:%M:%S") .. " UTC"
    end)
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return "unknown time"
end

local function buildReport(context, err, details)
    local message = safeToString(err)
    local contextText = safeToString(context)
    local traceback = message

    local traceOk, captured = pcall(function()
        return debug.traceback(message, 2)
    end)
    if traceOk and type(captured) == "string" and captured ~= "" then
        traceback = captured
    end

    local lines = {
        ("Avatar Copier v%s - error report"):format(CONFIG.VERSION),
        "Time: " .. utcTimestamp(),
        "Context: " .. contextText,
    }

    if type(details) == "table" then
        for _, line in ipairs(details) do
            table.insert(lines, safeToString(line))
        end
    end

    table.insert(lines, "Error: " .. message)
    table.insert(lines, "Traceback:")
    table.insert(lines, traceback)

    local report = table.concat(lines, "\n")
    if #report > MAX_CLIPBOARD_LENGTH then
        report = report:sub(1, MAX_CLIPBOARD_LENGTH) .. "\n...[truncated]"
    end

    return report
end

local function copyReport(kind, context, err, details)
    local report = buildReport(context, err, details)
    local copied, method = copyToClipboard(report)

    if copied then
        pcall(print, ("%s %s copied to the clipboard via %s."):format(
            LOG_PREFIX,
            kind,
            safeToString(method)
        ))
    else
        pcall(warn, ("%s Could not copy the %s to the clipboard (%s). Full report:"):format(
            LOG_PREFIX,
            string.lower(kind),
            safeToString(method)
        ))
        pcall(print, report)
    end

    return report, copied, method
end

local function reportError(context, err)
    local message = safeToString(err)
    pcall(warn, ("%s Unexpected error (%s): %s"):format(LOG_PREFIX, safeToString(context), message))
    return copyReport("Error report", context, err)
end

-- Used for handled technical failures (avatar fetch, model creation, attach).
-- These are not Lua crashes, but they still produce a useful report and must be
-- copied automatically. Plain validation errors (empty input, unknown player)
-- stay in the status card only.
local function reportFailure(context, err, details)
    local message = safeToString(err)
    pcall(warn, ("%s Preview failure (%s): %s"):format(LOG_PREFIX, safeToString(context), message))
    return copyReport("Failure report", context, err, details)
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
local destroyed = false

local overlay
local overlayFolder
local overlayWeld
local overlayConnection
local overlayJoints = {}
local hiddenInstances = {}
local activeTarget = nil
local apiTable = nil
local removeOverlay

local screenGui
local pillGui
local pill
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

local interfaceCollapsed = false

local function refreshClearButton()
    if clearButton and inputBox then
        clearButton.Visible = inputBox.Text ~= "" and not interfaceCollapsed
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
            local stale = nil
            for _, name in ipairs({ "AvatarCopierGui", "AvatarCopierPillGui" }) do
                local child = candidate.instance:FindFirstChild(name)
                if child then
                    stale = child
                end
            end
            return stale
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
    versionPill.Position = UDim2.new(1, -142, 0, 12)
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

    local minimizeButton = makeButton(
        titleBar,
        "Minimize",
        "–",
        UDim2.fromOffset(32, 32),
        UDim2.new(1, -80, 0, 6),
        Enum.Font.GothamBold,
        18,
        COLORS.textMuted,
        COLORS.surfaceAlt
    )
    styleButton(minimizeButton, COLORS.surfaceAlt, COLORS.surfaceHover)

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

    return closeButton, minimizeButton
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
        "Local preview — other players can't see it.",
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

    local closeButton, minimizeButton = buildHeader(titleBar)
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

    -- minimizing ------------------------------------------------------

    local bodyElements = {}
    for _, child in ipairs(window:GetChildren()) do
        if child ~= titleBar then
            table.insert(bodyElements, child)
        end
    end

    local collapsed = false
    local collapsedSize = UDim2.fromOffset(CONFIG.WINDOW_WIDTH, 44)
    local expandedSize = UDim2.fromOffset(CONFIG.WINDOW_WIDTH, CONFIG.WINDOW_HEIGHT)
    local bodyVisibility = {}

    local setCollapsed
    setCollapsed = function(value)
        if collapsed == value then
            return
        end
        collapsed = value
        interfaceCollapsed = value

        if value then
            bodyVisibility = {}
            for _, element in ipairs(bodyElements) do
                pcall(function()
                    bodyVisibility[element] = element.Visible
                    element.Visible = false
                end)
            end
        else
            for _, element in ipairs(bodyElements) do
                pcall(function()
                    local wasVisible = bodyVisibility[element]
                    if wasVisible == nil or wasVisible then
                        element.Visible = true
                    end
                end)
            end
            pcall(refreshClearButton)
        end

        pcall(function()
            minimizeButton.Text = value and "+" or "–"
        end)

        pcall(function()
            TweenService:Create(
                window,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = value and collapsedSize or expandedSize }
            ):Play()
        end)
    end

    track(minimizeButton.MouseButton1Click:Connect(function()
        safeCall("minimize button", function()
            setCollapsed(not collapsed)
        end)
    end))

    -- lifecycle ------------------------------------------------------

    -- A small floating pill so the interface can be brought back after
    -- closing it. It is a separate ScreenGui so it stays visible while the
    -- main interface is disabled.
    pillGui = Instance.new("ScreenGui")
    pillGui.Name = "AvatarCopierPillGui"
    pillGui.IgnoreGuiInset = true
    pillGui.ResetOnSpawn = false
    pillGui.DisplayOrder = 9998
    pillGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pillGui.Enabled = false

    local pillAttached = attachGui(pillGui)
    if pillAttached then
        pill = Instance.new("TextButton")
        pill.Name = "ReopenPill"
        pill.AnchorPoint = Vector2.new(1, 0)
        pill.Position = UDim2.new(1, -16, 0, 86)
        pill.Size = UDim2.fromOffset(44, 44)
        pill.BackgroundColor3 = CONFIG.ACCENT
        pill.BorderSizePixel = 0
        pill.Text = "A"
        pill.Font = Enum.Font.GothamBlack
        pill.TextSize = 16
        pill.TextColor3 = Color3.fromRGB(255, 255, 255)
        pill.AutoButtonColor = false
        pill.Active = true
        pill.Parent = pillGui
        makeCorner(pill, 22)
        makeStroke(pill, Color3.fromRGB(255, 255, 255), 1.5)

        local pillDragging = false
        local pillDragMoved = false
        local pillDragStart
        local pillStartX
        local pillStartY

        track(pill.InputBegan:Connect(function(input)
            safeCall("pill drag start", function()
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    pillDragging = true
                    pillDragMoved = false
                    pillDragStart = input.Position
                    pillStartX = pill.Position.X.Offset
                    pillStartY = pill.Position.Y.Offset
                end
            end)
        end))

        track(UserInputService.InputChanged:Connect(function(input)
            safeCall("pill drag move", function()
                if not pillDragging or not pillDragStart then
                    return
                end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement
                    and input.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end

                local delta = input.Position - pillDragStart
                if math.abs(delta.X) + math.abs(delta.Y) > 4 then
                    pillDragMoved = true
                end
                pill.Position = UDim2.new(
                    1,
                    pillStartX + delta.X,
                    0,
                    pillStartY + delta.Y
                )
            end)
        end))

        track(UserInputService.InputEnded:Connect(function(input)
            safeCall("pill drag end", function()
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    pillDragging = false
                end
            end)
        end))

        track(pill.MouseButton1Click:Connect(function()
            safeCall("reopen pill", function()
                if pillDragMoved then
                    pillDragMoved = false
                    return
                end
                if screenGui then
                    screenGui.Enabled = true
                end
                if pillGui then
                    pillGui.Enabled = false
                end
            end)
        end))
    else
        pcall(function()
            pillGui:Destroy()
        end)
        pillGui = nil
    end

    local function destroy()
        if destroyed then
            return
        end
        destroyed = true
        removeOverlay()
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        if screenGui then
            screenGui:Destroy()
        end
        if pillGui then
            pillGui:Destroy()
        end

        if type(getgenv) == "function" then
            local ok, env = pcall(getgenv)
            if ok and type(env) == "table" then
                if apiTable and env.AvatarCopier == apiTable then
                    env.AvatarCopier = nil
                end
                if env.AvatarCopierCleanup == destroy then
                    env.AvatarCopierCleanup = nil
                end
            end
        end
    end

    track(closeButton.MouseButton1Click:Connect(function()
        safeCall("close button", function()
            -- Closing hides the interface but keeps the avatar preview:
            -- the floating pill brings it back.
            if screenGui then
                screenGui.Enabled = false
            end
            if pillGui then
                pillGui.Enabled = true
            end
        end)
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
                return description, "server", serverPlayer.Name, serverPlayer.UserId, serverPlayer
            end

            -- Their character may not be loaded. We still know the ID, so use
            -- the avatar API as a fallback while keeping the display name.
            local ok, fetched = pcall(function()
                return Players:GetHumanoidDescriptionFromUserIdAsync(serverPlayer.UserId)
            end)
            if ok and typeof(fetched) == "Instance" and fetched:IsA("HumanoidDescription") then
                return fetched, "avatar_api", serverPlayer.Name, serverPlayer.UserId, serverPlayer
            end

            return nil, "fetch_failed", serverPlayer.Name, serverPlayer.UserId, serverPlayer
        end

        local ok, userId = pcall(function()
            return Players:GetUserIdFromNameAsync(value)
        end)
        if not ok or type(userId) ~= "number" or userId <= 0 then
            return nil, "not_found"
        end
        value = userId
    end

    local userId = value
    local ok, description = pcall(function()
        return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
    end)
    if ok and typeof(description) == "Instance" and description:IsA("HumanoidDescription") then
        return description, "avatar_api", nil, userId
    end

    -- The ID is valid but the description could not be fetched. A model can
    -- still sometimes be created directly from the ID, so keep it.
    return nil, "fetch_failed", nil, userId
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

-- ------------------------------------------------------ overlay pipeline

local function ensureOverlayFolder()
    if overlayFolder and overlayFolder.Parent == workspace then
        return overlayFolder
    end

    if overlayFolder then
        pcall(function()
            overlayFolder:Destroy()
        end)
        overlayFolder = nil
    end

    local stale = workspace:FindFirstChild(OVERLAY_FOLDER_NAME)
    if stale then
        pcall(function()
            stale:Destroy()
        end)
    end

    local folder = Instance.new("Folder")
    folder.Name = OVERLAY_FOLDER_NAME
    folder.Parent = workspace
    overlayFolder = folder
    return folder
end

local function cloneCharacter(character)
    if not character then
        return nil, "character is missing"
    end

    local wasArchivable = character.Archivable
    local ok, cloneOrError = pcall(function()
        character.Archivable = true
        return character:Clone()
    end)

    pcall(function()
        character.Archivable = wasArchivable
    end)

    if ok and typeof(cloneOrError) == "Instance" then
        return cloneOrError
    end

    return nil, cloneOrError
end

local function isValidModel(model)
    return typeof(model) == "Instance" and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function createModelFromDescription(description, rigType)
    if type(Players.CreateHumanoidModelFromDescriptionAsync) ~= "function" then
        return nil, "CreateHumanoidModelFromDescriptionAsync is unavailable"
    end

    local attempts = {}
    local function attempt(withVerification)
        local ok, modelOrError = pcall(function()
            if withVerification then
                return Players:CreateHumanoidModelFromDescriptionAsync(
                    description,
                    rigType,
                    Enum.AssetTypeVerification.Default
                )
            end
            return Players:CreateHumanoidModelFromDescriptionAsync(description, rigType)
        end)
        if ok and isValidModel(modelOrError) then
            return modelOrError
        end
        table.insert(attempts, safeToString(modelOrError))
        return nil
    end

    local model = attempt(true)
    if model then
        return model
    end

    model = attempt(false)
    if model then
        return model
    end

    return nil, table.concat(attempts, " | ")
end

local function createModelFromUserId(userId)
    if type(Players.CreateHumanoidModelFromUserIdAsync) ~= "function" then
        return nil, "CreateHumanoidModelFromUserIdAsync is unavailable"
    end

    local ok, modelOrError = pcall(function()
        return Players:CreateHumanoidModelFromUserIdAsync(userId)
    end)
    if ok and isValidModel(modelOrError) then
        return modelOrError
    end

    return nil, modelOrError
end

-- ApplyDescription is only legal on the client when the Humanoid belongs to a
-- rig this client created. This helper is deliberately never called with the
-- LocalPlayer's real Humanoid.
local APPLY_METHODS = {
    "ApplyDescriptionAsync",
    "ApplyDescriptionResetAsync",
    "ApplyDescription",
    "ApplyDescriptionReset",
}

local function applyDescriptionToClone(model, description)
    if not (typeof(description) == "Instance" and description:IsA("HumanoidDescription")) then
        return false, "Invalid HumanoidDescription"
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false, "The cloned model has no Humanoid"
    end

    local errors = {}
    for _, methodName in ipairs(APPLY_METHODS) do
        local method = humanoid[methodName]
        if type(method) == "function" then
            local ok, err = pcall(function()
                return method(humanoid, description, Enum.AssetTypeVerification.Default)
            end)
            if ok then
                return true, methodName
            end
            table.insert(errors, methodName .. ": " .. safeToString(err))
        end
    end

    return false, table.concat(errors, " | ")
end

local function applyPartialAppearance(model, description)
    if not (typeof(description) == "Instance" and description:IsA("HumanoidDescription")) then
        return false, "Invalid HumanoidDescription"
    end

    local changes = 0
    local errors = {}

    local bodyColors = model:FindFirstChild("BodyColors")
    if not bodyColors then
        bodyColors = Instance.new("BodyColors")
        bodyColors.Parent = model
    end

    local colorMap = {
        HeadColor = "HeadColor3",
        TorsoColor = "TorsoColor3",
        LeftArmColor = "LeftArmColor3",
        RightArmColor = "RightArmColor3",
        LeftLegColor = "LeftLegColor3",
        RightLegColor = "RightLegColor3",
    }

    for descriptionProperty, bodyProperty in pairs(colorMap) do
        local value = description[descriptionProperty]
        if value ~= nil then
            local ok, err = pcall(function()
                bodyColors[bodyProperty] = value
            end)
            if ok then
                changes = changes + 1
            else
                table.insert(errors, bodyProperty .. ": " .. safeToString(err))
            end
        end
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local scaleMap = {
        HeightScale = "BodyHeightScale",
        WidthScale = "BodyWidthScale",
        BodyDepthScale = "BodyDepthScale",
        HeadScale = "HeadScale",
        BodyTypeScale = "BodyTypeScale",
        ProportionScale = "ProportionScale",
    }

    if humanoid then
        for descriptionProperty, humanoidProperty in pairs(scaleMap) do
            local value = description[descriptionProperty]
            if type(value) == "number" then
                local ok, err = pcall(function()
                    humanoid[humanoidProperty] = value
                end)
                if ok then
                    changes = changes + 1
                else
                    table.insert(errors, humanoidProperty .. ": " .. safeToString(err))
                end
            end
        end
    end

    local clothing = {
        { className = "Shirt", descriptionProperty = "Shirt", templateProperty = "ShirtTemplate" },
        { className = "Pants", descriptionProperty = "Pants", templateProperty = "PantsTemplate" },
        { className = "ShirtGraphic", descriptionProperty = "GraphicTShirt", templateProperty = "Graphic" },
    }

    for _, item in ipairs(clothing) do
        local existing = model:FindFirstChildOfClass(item.className)
        if existing then
            existing:Destroy()
        end

        local assetId = description[item.descriptionProperty]
        if type(assetId) == "number" and assetId > 0 then
            local clothingInstance = Instance.new(item.className)
            clothingInstance[item.templateProperty] = "rbxassetid://" .. tostring(assetId)
            clothingInstance.Parent = model
            changes = changes + 1
        end
    end

    local head = model:FindFirstChild("Head")
    local faceId = description.Face
    if head and type(faceId) == "number" and faceId > 0 then
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") and child.Name == "Face" then
                child:Destroy()
            end
        end

        local face = Instance.new("Decal")
        face.Name = "Face"
        face.Texture = "rbxassetid://" .. tostring(faceId)
        face.Parent = head
        changes = changes + 1
    end

    if changes == 0 then
        local detail = "no usable appearance fields"
        if #errors > 0 then
            detail = detail .. ": " .. table.concat(errors, " | ")
        end
        return false, detail
    end

    return true, ("%d partial properties applied"):format(changes)
end

local function buildOverlayModel(target, localHumanoid)
    local errors = {}
    local function addError(label, err)
        table.insert(errors, label .. ": " .. safeToString(err))
    end

    local rigType = localHumanoid.RigType or Enum.HumanoidRigType.R15

    -- 1. Clone the target's live character when they are in this server. This
    --    preserves game-specific bodies, accessories, and scaling exactly.
    if target.sourcePlayer then
        local sourceCharacter = target.sourcePlayer.Character
        if sourceCharacter then
            local clone, err = cloneCharacter(sourceCharacter)
            if clone then
                return clone, "in-server character clone", errors, false
            end
            addError("in-server character clone", err)
        else
            addError("in-server character clone", "target character is not loaded")
        end
    end

    -- 2. Ask Roblox to build the avatar from the fetched description.
    if target.description then
        local model, err = createModelFromDescription(target.description, rigType)
        if model then
            return model, "CreateHumanoidModelFromDescriptionAsync", errors, false
        end
        addError("CreateHumanoidModelFromDescriptionAsync", err)
    end

    -- 3. Build it directly from the user ID.
    if target.userId then
        local model, err = createModelFromUserId(target.userId)
        if model then
            return model, "CreateHumanoidModelFromUserIdAsync", errors, false
        end
        addError("CreateHumanoidModelFromUserIdAsync", err)
    end

    -- 4. Clone the local character (a client-created rig) and apply the
    --    description to the clone. This is allowed because the clone only
    --    exists on this client.
    if target.description then
        local clone, err = cloneCharacter(LocalPlayer.Character)
        if clone then
            ensureOverlayFolder()
            clone.Parent = overlayFolder

            local applied, applyDetail = applyDescriptionToClone(clone, target.description)
            if applied then
                return clone, "local character clone + " .. applyDetail, errors, false
            end
            addError("local character clone + ApplyDescription", applyDetail)

            -- 5. Last resort: copy the description's colours, scale, clothing,
            --    and face onto the local clone. This is a partial preview.
            local partial, partialDetail = applyPartialAppearance(clone, target.description)
            if partial then
                return clone, "local character clone + partial appearance", errors, true
            end
            addError("local character clone + partial appearance", partialDetail)

            pcall(function()
                clone:Destroy()
            end)
        else
            addError("local character clone", err)
        end
    end

    return nil, nil, errors, false
end

local function sanitizeOverlay(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Script")
            or descendant:IsA("LocalScript")
            or descendant:IsA("ModuleScript")
            or descendant:IsA("Sound")
            or descendant:IsA("Tool")
            or descendant:IsA("ClickDetector")
            or descendant:IsA("ProximityPrompt")
            or descendant:IsA("BillboardGui")
            or descendant:IsA("BodyMover")
            or descendant:IsA("AlignPosition")
            or descendant:IsA("AlignOrientation")
            or descendant:IsA("LinearVelocity")
            or descendant:IsA("VectorForce")
            or descendant:IsA("Torque")
            or descendant:IsA("AngularVelocity") then
            pcall(function()
                descendant:Destroy()
            end)
        elseif descendant:IsA("BasePart") then
            pcall(function()
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
                descendant.Massless = true
                descendant.Anchored = false
            end)
        end
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function()
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end)
        pcall(function()
            humanoid.NameDisplayDistance = 0
        end)
        pcall(function()
            humanoid.HealthDisplayDistance = 0
        end)
        pcall(function()
            humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        end)
        pcall(function()
            humanoid.WalkSpeed = 0
        end)
        pcall(function()
            humanoid.JumpPower = 0
        end)
        pcall(function()
            humanoid.AutoRotate = false
        end)
        pcall(function()
            humanoid.PlatformStand = true
        end)
        pcall(function()
            humanoid.EvaluateStateMachine = false
        end)
        pcall(function()
            local disabledStates = {
                "FallingDown",
                "Ragdoll",
                "Jumping",
                "Freefall",
                "Climbing",
                "Seated",
                "Landed",
                "Running",
                "RunningNoPhysics",
                "StrafingNoPhysics",
                "Swimming",
                "GettingUp",
                "PlatformStand",
            }
            for _, stateName in ipairs(disabledStates) do
                local state = Enum.HumanoidStateType[stateName]
                if state then
                    humanoid:SetStateEnabled(state, false)
                end
            end
        end)
    end

    local root = model:FindFirstChild("HumanoidRootPart")
    if root then
        model.PrimaryPart = root
        pcall(function()
            root.Anchored = true
        end)
    end

    model.Name = "AvatarCopierPreview"
    model.Archivable = false
    return model
end

local function rememberHidden(instance, property, value, defaultValue)
    local ok, oldValue = pcall(function()
        return instance[property]
    end)
    if not ok then
        return
    end

    -- Roblox can expose unset properties as nil in some contexts. Keep a
    -- sensible default so reset always restores a usable value instead of
    -- leaving LocalTransparencyModifier/Transparency stuck at the hidden value.
    if oldValue == nil then
        oldValue = defaultValue
    end
    if oldValue == nil then
        return
    end

    table.insert(hiddenInstances, {
        instance = instance,
        property = property,
        value = oldValue,
    })

    pcall(function()
        instance[property] = value
    end)
end

local restoreLocalCharacter

local function hideLocalCharacter(character)
    restoreLocalCharacter()

    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            rememberHidden(descendant, "LocalTransparencyModifier", 1, 0)
        elseif descendant:IsA("Decal") then
            rememberHidden(descendant, "Transparency", 1, 0)
        elseif descendant:IsA("BillboardGui")
            or descendant:IsA("Highlight")
            or descendant:IsA("ParticleEmitter")
            or descendant:IsA("Trail")
            or descendant:IsA("Beam")
            or descendant:IsA("Fire")
            or descendant:IsA("Smoke")
            or descendant:IsA("Sparkles") then
            rememberHidden(descendant, "Enabled", false, true)
        end
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        rememberHidden(
            humanoid,
            "DisplayDistanceType",
            Enum.HumanoidDisplayDistanceType.None,
            Enum.HumanoidDisplayDistanceType.Viewer
        )
        rememberHidden(humanoid, "NameDisplayDistance", 0, 100)
        rememberHidden(humanoid, "HealthDisplayDistance", 0, 100)
        rememberHidden(
            humanoid,
            "HealthDisplayType",
            Enum.HumanoidHealthDisplayType.AlwaysOff,
            Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
        )
    end
end

function restoreLocalCharacter()
    for index = #hiddenInstances, 1, -1 do
        local entry = hiddenInstances[index]
        pcall(function()
            if entry.instance.Parent then
                entry.instance[entry.property] = entry.value
            end
        end)
    end
    hiddenInstances = {}
end

local function normalizeJointName(name)
    return (tostring(name):lower():gsub("[%s_%-]", ""))
end

local function collectJoints(character)
    local byName = {}
    local byParts = {}

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            byName[normalizeJointName(descendant.Name)] = descendant

            local part0 = descendant.Part0 and descendant.Part0.Name or ""
            local part1 = descendant.Part1 and descendant.Part1.Name or ""
            byParts[normalizeJointName(part0) .. "|" .. normalizeJointName(part1)] = descendant
        end
    end

    return byName, byParts
end

local function buildPoseMap(sourceCharacter)
    local sourceByName, sourceByParts = collectJoints(sourceCharacter)
    local map = {}

    for _, descendant in ipairs(overlay:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            local source = sourceByName[normalizeJointName(descendant.Name)]

            if not source then
                local part0 = descendant.Part0 and descendant.Part0.Name or ""
                local part1 = descendant.Part1 and descendant.Part1.Name or ""
                source = sourceByParts[normalizeJointName(part0) .. "|" .. normalizeJointName(part1)]
            end

            if source then
                table.insert(map, { overlayJoint = descendant, sourceJoint = source })
            end
        end
    end

    overlayJoints = map
end

local function mirrorPose()
    for _, joint in ipairs(overlayJoints) do
        local source = joint.sourceJoint
        local target = joint.overlayJoint
        if source.Parent and target.Parent then
            target.Transform = source.Transform
        end
    end
end

local function attachOverlay(model, localHumanoid, localCharacter)
    local overlayHumanoid = model:FindFirstChildOfClass("Humanoid")
    local overlayRoot = model:FindFirstChild("HumanoidRootPart")
        or (overlayHumanoid and overlayHumanoid.RootPart)
    local sourceRoot = localCharacter:FindFirstChild("HumanoidRootPart")
        or (localHumanoid and localHumanoid.RootPart)

    if not overlayRoot then
        return false, "the preview model has no HumanoidRootPart"
    end
    if not sourceRoot then
        return false, "your character has no HumanoidRootPart"
    end

    local folder = ensureOverlayFolder()
    if model.Parent ~= folder then
        model.Parent = folder
    end

    pcall(function()
        model:PivotTo(sourceRoot.CFrame)
    end)
    overlayRoot.CFrame = sourceRoot.CFrame

    overlay = model
    overlayWeld = nil
    hideLocalCharacter(localCharacter)
    buildPoseMap(localCharacter)

    -- The preview root is anchored and follows the real character every
    -- frame. Nothing is physically welded to the live rig, so the preview
    -- cannot inject impulses into the local Humanoid (this caused unwanted
    -- auto-jumping while walking on mobile).
    local followPose = function()
        if sourceRoot.CFrame then
            pcall(function()
                model:PivotTo(sourceRoot.CFrame)
            end)
            if overlayRoot.Parent then
                overlayRoot.CFrame = sourceRoot.CFrame
            end
        end
        mirrorPose()
    end

    local connection
    connection = RunService.RenderStepped:Connect(function()
        local ok = pcall(followPose)
        if not ok then
            pcall(function()
                connection:Disconnect()
            end)
            if overlayConnection == connection then
                overlayConnection = nil
            end
        end
    end)
    overlayConnection = connection

    return true
end

function removeOverlay()
    if overlayConnection then
        pcall(function()
            overlayConnection:Disconnect()
        end)
        overlayConnection = nil
    end

    overlayJoints = {}

    if overlayWeld then
        pcall(function()
            overlayWeld:Destroy()
        end)
        overlayWeld = nil
    end

    if overlay then
        pcall(function()
            overlay:Destroy()
        end)
        overlay = nil
    end

    local folder = overlayFolder
    if not folder then
        local ok, stale = pcall(function()
            return workspace:FindFirstChild(OVERLAY_FOLDER_NAME)
        end)
        if ok then
            folder = stale
        end
    end

    if folder then
        pcall(function()
            folder:Destroy()
        end)
    end
    overlayFolder = nil

    restoreLocalCharacter()
    activeTarget = nil
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
    lastCopyAt = os.clock()

    setBusy(true)
    setStatus("Resolving avatar...", "loading")

    local description, source, resolvedName, userId, sourcePlayer = resolveDescription(kind, value)

    if destroyed then
        busy = false
        return false, "Interface is closed."
    end

    local label = resolvedName or displayTarget
    local details = {
        "Target: " .. label,
        "Resolved user ID: " .. tostring(userId or "unknown"),
        "Avatar source: " .. tostring(source),
    }

    if not description and not userId then
        setBusy(false)

        if source == "not_found" then
            setStatus("Player not found. Check the spelling.", "error")
            return false, "Player not found."
        end

        local copied = reportFailure("copy/fetch", "Could not fetch an avatar description.", details)
        setStatus(
            copied
                and "Could not load that avatar. Error details copied to clipboard."
                or "Could not load that avatar. See the console for details.",
            "error"
        )
        return false, "Avatar fetch failed."
    end

    local humanoid = getLocalHumanoid()
    local character = LocalPlayer.Character
    if not humanoid or not character then
        setBusy(false)
        setStatus("Your character is not ready yet.", "error")
        return false, "Character not ready."
    end

    if destroyed then
        busy = false
        return false, "Interface is closed."
    end

    setStatus("Building avatar preview...", "loading")
    removeOverlay()

    local model, method, buildErrors, partial = buildOverlayModel({
        description = description,
        userId = userId,
        sourcePlayer = sourcePlayer,
    }, humanoid)

    if destroyed then
        if model then
            pcall(function()
                model:Destroy()
            end)
        end
        removeOverlay()
        busy = false
        return false, "Interface is closed."
    end

    if not model then
        setBusy(false)
        local buildDetails = {}
        for _, line in ipairs(details) do
            table.insert(buildDetails, line)
        end
        for _, line in ipairs(buildErrors) do
            table.insert(buildDetails, "Attempt: " .. line)
        end

        local copied = reportFailure(
            "copy/build",
            "All local avatar preview methods failed.",
            buildDetails
        )
        setStatus(
            copied
                and "Preview failed. Error details copied to clipboard."
                or "Preview failed. See the console for details.",
            "error"
        )
        return false, "Preview build failed."
    end

    sanitizeOverlay(model)
    local attachOk, attached, attachError = pcall(attachOverlay, model, humanoid, character)
    if not attachOk then
        attachError = attached
        attached = false
    end

    if destroyed then
        pcall(function()
            model:Destroy()
        end)
        removeOverlay()
        busy = false
        return false, "Interface is closed."
    end

    if not attached then
        pcall(function()
            model:Destroy()
        end)
        removeOverlay()
        setBusy(false)
        table.insert(details, "Build method: " .. tostring(method))
        local copied = reportFailure("copy/attach", attachError, details)
        setStatus(
            copied
                and "Could not attach the preview. Error details copied to clipboard."
                or "Could not attach the preview. See the console for details.",
            "error"
        )
        return false, "Preview attach failed."
    end

    activeTarget = {
        name = label,
        userId = userId,
        description = description,
        source = source,
        method = method,
    }

    setBusy(false)

    if partial then
        setStatus(("Partial preview of %s (local only)"):format(label), "warning")
        return true, "Partial local preview via " .. tostring(method)
    end

    setStatus(("Previewing %s (local only)"):format(label), "success")
    return true, "Local preview via " .. tostring(method)
end

local function resetAvatar()
    if destroyed then
        return false, "Interface is closed."
    end
    if busy then
        setStatus("Wait for the current copy to finish.", "warning")
        return false, "A copy is already in progress."
    end

    local hadPreview = overlay ~= nil or activeTarget ~= nil or #hiddenInstances > 0
    removeOverlay()

    if hadPreview then
        setStatus("Back to your own avatar.", "success")
        return true, "Your own avatar restored."
    end

    setStatus("Nothing to reset — you're already using your own avatar.", "idle")
    return false, "No preview active."
end

-- ------------------------------------------------------------- startup

-- Remove a stale overlay left behind if a previous execution was interrupted.
removeOverlay()

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

    track(LocalPlayer.CharacterAdded:Connect(function()
        safeCall("character respawn", function()
            if destroyed then
                return
            end

            if overlay then
                removeOverlay()
                setStatus("Character respawned. Copy the avatar again.", "warning")
            else
                restoreLocalCharacter()
            end
        end)
    end))

    -- Programmatic API for power users:
    --   AvatarCopier.copy("Roblox")   AvatarCopier.reset()   AvatarCopier.destroy()
    if type(getgenv) == "function" then
        local api = {
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
            isPreviewing = function()
                return overlay ~= nil
            end,
            getTarget = function()
                if not activeTarget then
                    return nil
                end
                return {
                    name = activeTarget.name,
                    userId = activeTarget.userId,
                    source = activeTarget.source,
                }
            end,
        }

        apiTable = api
        getgenv().AvatarCopier = api
        getgenv().AvatarCopierCleanup = destroyInterface
    end

    print(("%s v%s loaded. Client-side local preview."):format(LOG_PREFIX, CONFIG.VERSION))
end

local startOk = safeCall("startup", start)
if not startOk then
    pcall(setBusy, false)
    pcall(setStatus, "Startup failed. Details copied to clipboard.", "error")
end
