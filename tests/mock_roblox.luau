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
    CharacterAdded = true,
    CharacterRemoving = true,
    AncestryChanged = true,
}

local InstanceMT = {}
local METHODS = {}
local newInstance

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

function newInstance(className)
    local instance = setmetatable({}, InstanceMT)
    rawset(instance, "_props", { ClassName = className, Name = className })
    rawset(instance, "_children", {})
    rawset(instance, "_signals", {})
    rawset(instance, "_destroyed", false)

    if className == "Part"
        or className == "BasePart"
        or className == "MeshPart"
        or className == "HumanoidRootPart" then
        props(instance).LocalTransparencyModifier = 0
    elseif className == "Decal" then
        props(instance).Transparency = 0
    end

    return instance
end

local CLASS_PARENTS = {
    BasePart = "PVInstance",
    Part = "BasePart",
    MeshPart = "BasePart",
    HumanoidRootPart = "Part",
    Shirt = "Clothing",
    Pants = "Clothing",
    ShirtGraphic = "Clothing",
    Clothing = "Instance",
    BodyVelocity = "BodyMover",
    BodyGyro = "BodyMover",
    BodyPosition = "BodyMover",
    BodyForce = "BodyMover",
    BodyMover = "Instance",
    LocalScript = "Script",
    Script = "LuaSourceContainer",
    ModuleScript = "LuaSourceContainer",
    Animation = "Instance",
    AnimationTrack = "Instance",
    Animator = "Instance",
}

function METHODS:IsA(className)
    local current = props(self).ClassName
    while current do
        if current == className then
            return true
        end
        current = CLASS_PARENTS[current]
    end
    return false
end

function METHODS:GetChildren()
    local snapshot = {}
    for index, child in ipairs(children(self)) do
        snapshot[index] = child
    end
    return snapshot
end

function METHODS:GetDescendants()
    local result = {}

    for _, child in ipairs(children(self)) do
        table.insert(result, child)
        for _, descendant in ipairs(child:GetDescendants()) do
            table.insert(result, descendant)
        end
    end

    return result
end

function METHODS:Clone()
    if props(self).__failClone then
        error("Clone failed for " .. tostring(props(self).Name))
    end

    local copy = newInstance(props(self).ClassName)
    for key, value in pairs(props(self)) do
        if key ~= "Parent" then
            props(copy)[key] = value
        end
    end

    -- A cloned Humanoid is a client-created rig, even if the source was a
    -- server-owned character. ApplyDescription is allowed on the clone.
    if props(copy).ClassName == "Humanoid" then
        props(copy)._backendOwned = false
    end

    for _, child in ipairs(children(self)) do
        setParent(child:Clone(), copy)
    end

    return copy
end

function METHODS:PivotTo(_cframe)
    return self
end

function METHODS:LoadAnimation(animation)
    local track = newInstance("AnimationTrack")
    track.Name = (animation and animation.Name or "Track") .. "Track"
    track.Animation = animation
    track.IsPlaying = false
    track.Speed = 1
    track.Weight = 1
    track.TimePosition = 0
    setParent(track, self)
    return track
end

function METHODS:GetPlayingAnimationTracks()
    local result = {}
    for _, child in ipairs(children(self)) do
        if props(child).ClassName == "AnimationTrack" and props(child).IsPlaying then
            table.insert(result, child)
        end
    end
    return result
end

function METHODS:Play(_fadeIn)
    props(self).IsPlaying = true
end

function METHODS:Stop(_fadeOut)
    props(self).IsPlaying = false
end

function METHODS:AdjustSpeed(speed)
    if type(speed) == "number" then
        props(self).Speed = speed
    end
end

function METHODS:AdjustWeight(weight)
    if type(weight) == "number" then
        props(self).Weight = weight
    end
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

RunService = newInstance("RunService")
RunService.Parent = game
RunService.RenderStepped = newSignal()
RunService.Heartbeat = newSignal()
services.RunService = RunService

-- ---------------------------------------------------------------- players

local ownDescription = newInstance("HumanoidDescription")
ownDescription.Name = "OriginalDescription"

local apiDescription = newInstance("HumanoidDescription")
apiDescription.Name = "ApiDescription"

local serverDescription = newInstance("HumanoidDescription")
serverDescription.Name = "ServerDescription"

apiDescription.HeadColor = Color3.fromRGB(220, 120, 80)
apiDescription.TorsoColor = Color3.fromRGB(60, 120, 220)
apiDescription.Shirt = 111
apiDescription.Pants = 222
apiDescription.Face = 333
apiDescription.HeightScale = 1.1
apiDescription.WidthScale = 0.95

local PlayerGui = newInstance("PlayerGui")
PlayerGui.Name = "PlayerGui"

local LocalPlayer = newInstance("Player")
LocalPlayer.Name = "LocalTester"
LocalPlayer.DisplayName = "LocalTester"
LocalPlayer.UserId = 1
LocalPlayer.Parent = Players
Players.LocalPlayer = LocalPlayer
PlayerGui.Parent = LocalPlayer

local function mockCFrame(x, y, z)
    return { Position = { X = x, Y = y, Z = z } }
end

local function makeRig(name, description, backendOwned, includeGhost)
    local model = newInstance("Model")
    model.Name = name
    model.Parent = workspace

    local rigHumanoid = newInstance("Humanoid")
    rigHumanoid.Name = "Humanoid"
    rigHumanoid.Parent = model
    rigHumanoid.RigType = Enum.HumanoidRigType.R15
    rigHumanoid._backendOwned = backendOwned == true
    rigHumanoid.__description = description

    local rigAnimator = newInstance("Animator")
    rigAnimator.Name = "Animator"
    rigAnimator.Parent = rigHumanoid

    if includeGhost ~= false then
        -- A looping animation that stands in for whatever animations a live
        -- target's Animator might carry. A clean preview must NOT inherit it:
        -- sanitizeOverlay removes it and attachOverlay builds a fresh Animator.
        local ghostAnimation = newInstance("Animation")
        ghostAnimation.Name = "GhostAnimation"
        ghostAnimation.AnimationId = "rbxassetid://9001"
        ghostAnimation.Parent = rigAnimator

        local ghostTrack = newInstance("AnimationTrack")
        ghostTrack.Name = "GhostTrack"
        ghostTrack.Animation = ghostAnimation
        ghostTrack.IsPlaying = true
        ghostTrack.Parent = rigAnimator
    end

    local root = newInstance("HumanoidRootPart")
    root.Name = "HumanoidRootPart"
    root.CFrame = mockCFrame(10, 5, 0)
    root.Parent = model
    rigHumanoid.RootPart = root

    local torso = newInstance("BasePart")
    torso.Name = "Torso"
    torso.Parent = model

    local head = newInstance("BasePart")
    head.Name = "Head"
    head.Parent = model

    local neck = newInstance("Motor6D")
    neck.Name = "Neck"
    neck.Part0 = torso
    neck.Part1 = head
    neck.Transform = { Angle = 0 }
    neck.Parent = torso

    local bodyColors = newInstance("BodyColors")
    bodyColors.Name = "BodyColors"
    bodyColors.Parent = model

    local shirt = newInstance("Shirt")
    shirt.Name = "Shirt"
    shirt.ShirtTemplate = "rbxassetid://1"
    shirt.Parent = model

    local face = newInstance("Decal")
    face.Name = "Face"
    face.Texture = "rbxassetid://2"
    face.Parent = head

    function rigHumanoid:GetAppliedDescription()
        return self.Applied or self.__description or ownDescription
    end

    local function recordApply(self, appliedDescription)
        self.Applied = appliedDescription
        self.ApplyCount = (self.ApplyCount or 0) + 1
    end

    local function assertClientOwned(self, method)
        if self._backendOwned then
            error(("Humanoid::%s() can only be called by the backend server"):format(method))
        end
        if self._denyApply then
            error("ApplyDescription is unavailable for this test rig")
        end
    end

    function rigHumanoid:ApplyDescriptionAsync(appliedDescription)
        assertClientOwned(self, "ApplyDescription")
        recordApply(self, appliedDescription)
    end

    function rigHumanoid:ApplyDescriptionResetAsync(appliedDescription)
        assertClientOwned(self, "ApplyDescriptionReset")
        recordApply(self, appliedDescription)
    end

    function rigHumanoid:ApplyDescription(appliedDescription)
        assertClientOwned(self, "ApplyDescription")
        recordApply(self, appliedDescription)
    end

    function rigHumanoid:ApplyDescriptionReset(appliedDescription)
        assertClientOwned(self, "ApplyDescriptionReset")
        recordApply(self, appliedDescription)
    end

    return model, rigHumanoid
end

local character, humanoid = makeRig("LocalTester", ownDescription, true, false)
LocalPlayer.Character = character

local serverPlayer = newInstance("Player")
serverPlayer.Name = "ServerFriend"
serverPlayer.DisplayName = "ServerFriend"
serverPlayer.UserId = 222
serverPlayer.Parent = Players

local serverCharacter = makeRig("ServerFriend", serverDescription, true)
serverPlayer.Character = serverCharacter

-- A leftover constraint mover on the server rig must not survive sanitizing.
local serverMover = newInstance("LinearVelocity")
serverMover.Name = "StickyMover"
serverMover.Parent = serverCharacter

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

Players.DescriptionCreateCount = 0
Players.UserIdCreateCount = 0
Players.LastDescriptionRigType = nil

Players.CreateHumanoidModelFromDescriptionAsync = function(self, description, rigType, _verification)
    self.DescriptionCreateCount = self.DescriptionCreateCount + 1
    self.LastDescriptionRigType = rigType

    local model, modelHumanoid = makeRig("DescriptionPreview", description, false)
    modelHumanoid:ApplyDescriptionAsync(description)
    return model
end

Players.CreateHumanoidModelFromUserIdAsync = function(self, userId)
    self.UserIdCreateCount = self.UserIdCreateCount + 1
    local description = self:GetHumanoidDescriptionFromUserIdAsync(userId)
    local model, modelHumanoid = makeRig("UserIdPreview", description, false)
    modelHumanoid:ApplyDescriptionAsync(description)
    return model
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
