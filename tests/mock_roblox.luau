--!nocheck
-- Minimal Roblox client mock used by the headless test suite.
--
-- It is NOT a Roblox emulator. It implements only the API surface that
-- src/CopyAvatar.lua touches, so the tests can assert real behaviour:
-- GUI parenting, the copy pipeline, the reset button, and cleanup.
--
-- TEST_MOBILE is injected by tests/run.sh before this file is concatenated.

local IS_MOBILE = TEST_MOBILE ~= false

local warnings = {}

warn = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    table.insert(warnings, table.concat(parts, " "))
end

-- ------------------------------------------------------------ instances

local EVENT_NAMES = {
    MouseButton1Click = true,
    MouseEnter = true,
    MouseLeave = true,
    InputBegan = true,
    InputChanged = true,
    InputEnded = true,
    FocusLost = true,
    Focused = true,
    Activated = true,
    Changed = true,
}

local InstanceMT = {}
local METHODS = {}

local function props(instance)
    return rawget(instance, "_props")
end

local function children(instance)
    return rawget(instance, "_children")
end

local function isInstance(value)
    return type(value) == "table" and getmetatable(value) == InstanceMT
end

local function newSignal()
    local handlers = {}
    local signal = {}

    function signal:Connect(handler)
        table.insert(handlers, handler)

        local connection = {}

        function connection:Disconnect()
            for index, candidate in ipairs(handlers) do
                if candidate == handler then
                    table.remove(handlers, index)
                    break
                end
            end
        end

        return connection
    end

    function signal:Fire(...)
        local snapshot = {}
        for index, handler in ipairs(handlers) do
            snapshot[index] = handler
        end

        for _, handler in ipairs(snapshot) do
            handler(...)
        end
    end

    return signal
end

local function setParent(instance, parent)
    if parent ~= nil and not isInstance(parent) then
        error("Parent must be an Instance", 2)
    end

    local current = props(instance).Parent
    if current then
        for index, sibling in ipairs(children(current)) do
            if sibling == instance then
                table.remove(children(current), index)
                break
            end
        end
    end

    props(instance).Parent = parent

    if parent then
        table.insert(children(parent), instance)
    end
end

function InstanceMT.__index(instance, key)
    local method = METHODS[key]
    if method then
        return method
    end

    local signals = rawget(instance, "_signals")
    if signals[key] then
        return signals[key]
    end

    if EVENT_NAMES[key] then
        local signal = newSignal()
        signals[key] = signal
        return signal
    end

    return props(instance)[key]
end

function InstanceMT.__newindex(instance, key, value)
    if key == "Parent" then
        setParent(instance, value)
        return
    end

    props(instance)[key] = value
end

local function newInstance(className)
    local instance = setmetatable({}, InstanceMT)
    rawset(instance, "_props", { ClassName = className, Name = className })
    rawset(instance, "_children", {})
    rawset(instance, "_signals", {})
    rawset(instance, "_destroyed", false)
    return instance
end

function METHODS:IsA(className)
    return props(self).ClassName == className
end

function METHODS:GetChildren()
    local snapshot = {}
    for index, child in ipairs(children(self)) do
        snapshot[index] = child
    end
    return snapshot
end

function METHODS:FindFirstChild(name)
    for _, child in ipairs(children(self)) do
        if props(child).Name == name then
            return child
        end
    end
    return nil
end

function METHODS:FindFirstChildOfClass(className)
    for _, child in ipairs(children(self)) do
        if props(child).ClassName == className then
            return child
        end
    end
    return nil
end

function METHODS:WaitForChild(name, _timeout)
    return self:FindFirstChild(name)
end

function METHODS:IsDescendantOf(ancestor)
    local current = props(self).Parent
    while current do
        if current == ancestor then
            return true
        end
        current = props(current).Parent
    end
    return false
end

function METHODS:Destroy()
    if rawget(self, "_destroyed") then
        return
    end
    rawset(self, "_destroyed", true)

    for _, child in ipairs(self:GetChildren()) do
        child:Destroy()
    end

    setParent(self, nil)
end

-- ------------------------------------------------------------- datatypes

local enumCache = {}

Enum = setmetatable({}, {
    __index = function(_, categoryName)
        local category = enumCache[categoryName]
        if category then
            return category
        end

        local items = {}
        category = setmetatable({}, {
            __index = function(_, itemName)
                local token = items[itemName]
                if not token then
                    token = { Name = itemName, EnumType = categoryName }
                    items[itemName] = token
                end
                return token
            end,
        })
        enumCache[categoryName] = category
        return category
    end,
})

Color3 = {
    fromRGB = function(red, green, blue)
        return { R = red / 255, G = green / 255, B = blue / 255 }
    end,
    new = function(red, green, blue)
        return { R = red or 0, G = green or 0, B = blue or 0 }
    end,
}

UDim = {
    new = function(scale, offset)
        return { Scale = scale, Offset = offset }
    end,
}

UDim2 = {
    new = function(xScale, xOffset, yScale, yOffset)
        return {
            X = { Scale = xScale, Offset = xOffset },
            Y = { Scale = yScale, Offset = yOffset },
        }
    end,
    fromOffset = function(x, y)
        return UDim2.new(0, x, 0, y)
    end,
    fromScale = function(x, y)
        return UDim2.new(x, 0, y, 0)
    end,
}

Vector2 = {
    new = function(x, y)
        return { X = x, Y = y }
    end,
}

TweenInfo = {
    new = function(time)
        return { Time = time }
    end,
}

-- ------------------------------------------------------------------ time

local clock = 1000

os = {
    clock = function()
        return clock
    end,
    time = function()
        return 0
    end,
    date = function()
        return ""
    end,
}

local function advanceClock(seconds)
    clock = clock + seconds
end

task = {
    spawn = function(callback, ...)
        callback(...)
    end,
    defer = function(callback, ...)
        callback(...)
    end,
    wait = function(seconds)
        local duration = seconds or 0
        clock = clock + duration
        return duration
    end,
}

-- -------------------------------------------------------------- services

game = newInstance("DataModel")
workspace = newInstance("Workspace")

local services = {}

game.GetService = function(_, name)
    local service = services[name]
    if not service then
        error("Unknown service: " .. tostring(name))
    end
    return service
end

workspace.CurrentCamera = {
    ViewportSize = { X = 1920, Y = 1080 },
}

Players = newInstance("Players")
Players.Parent = game
services.Players = Players

local coreGui = newInstance("CoreGui")
coreGui.Parent = game
services.CoreGui = coreGui

local hiddenContainer = newInstance("Folder")
hiddenContainer.Name = "HiddenGui"
hiddenContainer.Parent = coreGui

UserInputService = newInstance("UserInputService")
UserInputService.Parent = game
UserInputService.TouchEnabled = IS_MOBILE
UserInputService.KeyboardEnabled = not IS_MOBILE
services.UserInputService = UserInputService

TweenService = newInstance("TweenService")
TweenService.Parent = game
services.TweenService = TweenService

function TweenService:Create(instance, _info, goal)
    return {
        Play = function()
            for key, value in pairs(goal) do
                instance[key] = value
            end
        end,
    }
end

-- ---------------------------------------------------------------- players

local ownDescription = newInstance("HumanoidDescription")
ownDescription.Name = "OriginalDescription"

local apiDescription = newInstance("HumanoidDescription")
apiDescription.Name = "ApiDescription"

local serverDescription = newInstance("HumanoidDescription")
serverDescription.Name = "ServerDescription"

local PlayerGui = newInstance("PlayerGui")
PlayerGui.Name = "PlayerGui"

local LocalPlayer = newInstance("Player")
LocalPlayer.Name = "LocalTester"
LocalPlayer.DisplayName = "LocalTester"
LocalPlayer.UserId = 1
LocalPlayer.Parent = Players
Players.LocalPlayer = LocalPlayer
PlayerGui.Parent = LocalPlayer

local character = newInstance("Model")
character.Name = "LocalTester"
character.Parent = workspace

local humanoid = newInstance("Humanoid")
humanoid.Parent = character
LocalPlayer.Character = character

local function recordApply(description)
    humanoid.Applied = description
    humanoid.ApplyCount = (humanoid.ApplyCount or 0) + 1
end

function humanoid:GetAppliedDescription()
    return self.Applied or ownDescription
end

function humanoid:ApplyDescriptionAsync(description)
    recordApply(description)
end

function humanoid:ApplyDescriptionResetAsync(description)
    recordApply(description)
end

function humanoid:ApplyDescription(description)
    recordApply(description)
end

function humanoid:ApplyDescriptionReset(description)
    recordApply(description)
end

LocalPlayer.ClearCharacterAppearance = function() end

local serverPlayer = newInstance("Player")
serverPlayer.Name = "ServerFriend"
serverPlayer.DisplayName = "ServerFriend"
serverPlayer.UserId = 222
serverPlayer.Parent = Players

local serverCharacter = newInstance("Model")
serverCharacter.Parent = workspace

local serverHumanoid = newInstance("Humanoid")
serverHumanoid.Parent = serverCharacter
serverHumanoid.GetAppliedDescription = function()
    return serverDescription
end

serverPlayer.Character = serverCharacter

Players.GetPlayers = function()
    return { LocalPlayer, serverPlayer }
end

Players.GetUserIdFromNameAsync = function(_, username)
    if username == "TestUser" then
        return 12345
    end
    error("Unknown user: " .. tostring(username))
end

Players.GetHumanoidDescriptionFromUserIdAsync = function(_, userId)
    if userId == 12345 or userId == 999 then
        return apiDescription
    end
    error("Unknown user id: " .. tostring(userId))
end

-- --------------------------------------------------------------- executor

local ENV = {}

getgenv = function()
    return ENV
end

ENV.setclipboard = function(text)
    ENV.__clipboard = text
end

gethui = function()
    return hiddenContainer
end

Instance = {
    new = newInstance,
}

local realTypeof = typeof

typeof = function(value)
    if isInstance(value) then
        return "Instance"
    end
    return realTypeof(value)
end
