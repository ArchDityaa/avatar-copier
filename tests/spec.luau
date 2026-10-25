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
equal(api and api.version, "1.1.0", "version is 1.1.0")

local expectedParent = IS_MOBILE and PlayerGui or hiddenContainer
local gui = expectedParent:FindFirstChild("AvatarCopierGui")
check(gui ~= nil, "ScreenGui exists in " .. expectedParent.Name)
equal(gui and gui.Parent, expectedParent, "ScreenGui attached to " .. expectedParent.Name)
equal(gui and gui.Enabled, true, "ScreenGui is enabled")

local window = gui and gui:FindFirstChild("Window")
check(window ~= nil, "Window exists")
equal(window and window.Parent, gui, "Window is parented to the ScreenGui (v1.0.0 regression)")
equal(window and window.Size.X.Offset, 320, "window uses the 320px design width")
equal(window and window.Size.Y.Offset, 272, "window uses the 272px design height")

local uiScale = window and window:FindFirstChildOfClass("UIScale")
check(uiScale ~= nil, "responsive UIScale exists")
check(uiScale and uiScale.Scale >= 0.8 and uiScale.Scale <= 1, "UIScale stays within bounds")

local titleBar = window and window:FindFirstChild("TitleBar")
local logo = titleBar and titleBar:FindFirstChild("Logo")
local versionPill = titleBar and titleBar:FindFirstChild("VersionPill")
local input = window and window:FindFirstChild("TargetInput")
local copyButton = window and window:FindFirstChild("Copy")
local resetButton = window and window:FindFirstChild("Reset")
local clearButton = window and window:FindFirstChild("Clear")
local searchIcon = window and window:FindFirstChild("SearchIcon")
local inputStroke = input and input:FindFirstChildOfClass("UIStroke")
local statusCard = window and window:FindFirstChild("StatusCard")
local statusLabel = statusCard and statusCard:FindFirstChild("StatusText")
local statusDot = statusCard and statusCard:FindFirstChild("Dot")

check(titleBar ~= nil, "title bar exists")
check(logo ~= nil, "logo tile exists")
check(versionPill ~= nil, "version pill exists")
check(input ~= nil, "input box exists")
check(copyButton ~= nil, "copy button exists")
check(resetButton ~= nil, "reset button exists")
check(clearButton ~= nil, "clear button exists")
check(searchIcon ~= nil, "search icon exists")
check(inputStroke ~= nil, "input focus ring exists")
check(statusCard ~= nil, "status card exists")
check(statusLabel ~= nil, "status label exists")
check(statusDot ~= nil, "status indicator exists")
check(window and window:FindFirstChild("Helper") ~= nil, "input helper text exists")
check(window and window:FindFirstChild("Footer") ~= nil, "privacy footer exists")

if input and clearButton then
    equal(clearButton.Visible, false, "clear button hidden while input is empty")

    input.Text = "abc"
    input.Changed:Fire("Text")
    equal(clearButton.Visible, true, "clear button appears when input has text")

    clearButton.MouseButton1Click:Fire()
    equal(input.Text, "", "clear button empties the input")
    equal(clearButton.Visible, false, "clear button hides after clearing")
end

if input and inputStroke then
    input.Focused:Fire()
    equal(inputStroke.Color, CONFIG.ACCENT, "input focus ring uses the accent colour")

    input.FocusLost:Fire(false)
    equal(inputStroke.Color, COLORS.stroke, "input focus ring resets on blur")
end

if input and copyButton and statusLabel and statusDot and statusCard then
    input.Text = "ServerFriend"
    copyButton.MouseButton1Click:Fire()
    equal(humanoid.Applied, serverDescription, "in-server player reuses the live HumanoidDescription")
    contains(statusLabel.Text, "Copied from ServerFriend (local only)", "status reports the server copy")
    equal(statusDot.BackgroundColor3, COLORS.success, "success status uses the success colour")
    equal(statusCard.BackgroundColor3, STATUS_THEMES.success.background, "success status tints the card")
    equal(copyButton.Text, "Copy avatar", "copy button label restored")
    equal(copyButton.Active, true, "copy button re-enabled after a copy")

    advanceClock(2)

    input.Text = "TestUser"
    copyButton.MouseButton1Click:Fire()
    equal(humanoid.Applied, apiDescription, "username resolved through the avatar API")
    contains(statusLabel.Text, "Copied from TestUser (local only)", "status reports the API copy")

    copyButton.MouseButton1Click:Fire()
    contains(statusLabel.Text, "Please wait a moment", "cooldown blocks an immediate re-copy")
    equal(statusDot.BackgroundColor3, COLORS.warning, "cooldown status uses the warning colour")
    equal(humanoid.Applied, apiDescription, "blocked copy does not re-apply the description")

    advanceClock(2)
    input.Text = "nobody"
    copyButton.MouseButton1Click:Fire()
    contains(statusLabel.Text, "Player not found", "unknown username reports not found")
    equal(statusDot.BackgroundColor3, COLORS.error, "not-found status uses the error colour")

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
