--!nocheck
-- Assertions for the headless Roblox mock. tests/run.sh concatenates:
--   mocks + src/CopyAvatar.lua + this file
-- so every top-level local declared by the mocks/script is visible here.

local failures = 0
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if condition then
        print(("  ok   %s"):format(message))
    else
        failures = failures + 1
        print(("  FAIL %s"):format(message))
    end
end

local function equal(actual, expected, message)
    checks = checks + 1
    if actual == expected then
        print(("  ok   %s"):format(message))
    else
        failures = failures + 1
        print(("  FAIL %s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
    end
end

local function contains(text, fragment, message)
    check(type(text) == "string" and string.find(text, fragment, 1, true) ~= nil, message)
end

print("== avatar copier headless tests ==")

local api = getgenv().AvatarCopier
check(api ~= nil, "API is exposed through getgenv()")
equal(api and api.version, "1.0.1", "version is 1.0.1")

local expectedParent = IS_MOBILE and PlayerGui or hiddenContainer
local gui = expectedParent:FindFirstChild("AvatarCopierGui")
check(gui ~= nil, "ScreenGui exists in " .. expectedParent.Name)
equal(gui and gui.Parent, expectedParent, "ScreenGui attached to " .. expectedParent.Name)
equal(gui and gui.Enabled, true, "ScreenGui is enabled")

local window = gui and gui:FindFirstChild("Window")
check(window ~= nil, "Window exists")
equal(window and window.Parent, gui, "Window is parented to the ScreenGui (v1.0.0 regression)")

local titleBar = window and window:FindFirstChild("TitleBar")
local input = window and window:FindFirstChild("TargetInput")
local copyButton = window and window:FindFirstChild("Copy")
local resetButton = window and window:FindFirstChild("Reset")
check(titleBar ~= nil, "title bar exists")
check(input ~= nil, "input box exists")
check(copyButton ~= nil, "copy button exists")
check(resetButton ~= nil, "reset button exists")

local statusLabel
if window then
    for _, child in ipairs(window:GetChildren()) do
        if child.ClassName == "TextLabel" and child.TextWrapped == true then
            statusLabel = child
        end
    end
end
check(statusLabel ~= nil, "status label exists")

if input and copyButton and statusLabel then
    input.Text = "ServerFriend"
    copyButton.MouseButton1Click:Fire()
    equal(humanoid.Applied, serverDescription, "in-server player reuses the live HumanoidDescription")
    contains(statusLabel.Text, "Copied from ServerFriend (local only)", "status reports the server copy")
    equal(copyButton.Text, "Copy", "copy button label restored")

    advanceClock(2)

    input.Text = "TestUser"
    copyButton.MouseButton1Click:Fire()
    equal(humanoid.Applied, apiDescription, "username resolved through the avatar API")
    contains(statusLabel.Text, "Copied from TestUser (local only)", "status reports the API copy")

    copyButton.MouseButton1Click:Fire()
    contains(statusLabel.Text, "Please wait a moment", "cooldown blocks an immediate re-copy")
    equal(humanoid.Applied, apiDescription, "blocked copy does not re-apply the description")

    advanceClock(2)
    input.Text = "nobody"
    copyButton.MouseButton1Click:Fire()
    contains(statusLabel.Text, "Player not found", "unknown username reports not found")

    advanceClock(2)
    input.Text = "   "
    copyButton.MouseButton1Click:Fire()
    contains(statusLabel.Text, "Enter a username or user ID first", "empty input is rejected")
end

if resetButton and statusLabel then
    resetButton.MouseButton1Click:Fire()
    equal(humanoid.Applied, ownDescription, "reset restores the original description")
    contains(statusLabel.Text, "Restored your own avatar", "status confirms the reset")
end

if api and gui then
    api.destroy()
    equal(gui.Parent, nil, "destroy detaches the ScreenGui")
    equal(getgenv().AvatarCopier, nil, "destroy clears the global API")
end

equal(#warnings, 0, "no warnings during the happy path")

print(("%d checks, %d failed"):format(checks, failures))
if failures > 0 then
    error(("%d test(s) failed"):format(failures))
end
