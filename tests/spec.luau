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
        print(("  FAIL %s (expected %s, got %s)"):format(
            message,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function contains(text, fragment, message)
    check(type(text) == "string" and string.find(text, fragment, 1, true) ~= nil, message)
end

local function overlayFolder()
    return workspace:FindFirstChild("AvatarCopierOverlay")
end

local function findPreview()
    local folder = overlayFolder()
    return folder and folder:FindFirstChild("AvatarCopierPreview")
end

local function overlayNeck(model)
    local torso = model and model:FindFirstChild("Torso")
    return torso and torso:FindFirstChild("Neck")
end

print("== avatar copier headless tests ==")

local api = getgenv().AvatarCopier
check(api ~= nil, "API is exposed through getgenv()")
equal(api and api.version, "1.3.0", "version is 1.3.0")

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
local footer = window and window:FindFirstChild("Footer")

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
check(footer ~= nil, "privacy footer exists")
contains(footer and footer.Text, "Local preview", "footer explains that the preview is local")

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

local localRoot = character:FindFirstChild("HumanoidRootPart")
local localFace = character:FindFirstChild("Head"):FindFirstChild("Face")
local sourceNeck = character:FindFirstChild("Torso"):FindFirstChild("Neck")

-- In-server avatar: clone the live character and render it as a local overlay.
if input and copyButton and statusLabel and statusDot and statusCard then
    input.Text = "ServerFriend"
    copyButton.MouseButton1Click:Fire()

    local preview = findPreview()
    local previewRoot = preview and preview:FindFirstChild("HumanoidRootPart")
    local previewHumanoid = preview and preview:FindFirstChildOfClass("Humanoid")
    local weld = previewRoot and previewRoot:FindFirstChild("AvatarCopierWeld")

    check(preview ~= nil, "copy creates an AvatarCopierPreview overlay")
    equal(preview and preview.Parent, overlayFolder(), "overlay is parented to the overlay folder")
    check(previewHumanoid ~= nil, "overlay has a Humanoid")
    equal(humanoid.ApplyCount, nil, "the real LocalPlayer Humanoid is never used for ApplyDescription")
    equal(localRoot.LocalTransparencyModifier, 1, "the real LocalPlayer character is hidden locally")
    equal(localFace.Transparency, 1, "decals on the real character are hidden locally")
    check(weld ~= nil, "overlay is welded to the real character")
    equal(weld and weld.Part0, localRoot, "weld Part0 is the real HumanoidRootPart")
    equal(weld and weld.Part1, previewRoot, "weld Part1 is the overlay HumanoidRootPart")
    equal(previewRoot and previewRoot.CanCollide, false, "overlay parts do not collide")
    equal(previewRoot and previewRoot.CanTouch, false, "overlay parts do not receive touches")
    equal(previewRoot and previewRoot.CanQuery, false, "overlay parts are excluded from raycasts")
    equal(previewHumanoid and previewHumanoid.WalkSpeed, 0, "overlay Humanoid cannot walk")
    equal(previewHumanoid and previewHumanoid.PlatformStand, true, "overlay Humanoid is platform-standing")
    equal(previewHumanoid and previewHumanoid.DisplayDistanceType.Name, "None", "overlay hides name/health displays")
    equal(api.isPreviewing(), true, "API reports an active preview")
    equal(api.getTarget() and api.getTarget().name, "ServerFriend", "API reports the preview target")
    equal(api.getTarget() and api.getTarget().userId, 222, "API reports the target user ID")

    contains(statusLabel.Text, "Previewing ServerFriend (local only)", "status reports the local preview")
    equal(statusDot.BackgroundColor3, COLORS.success, "success status uses the success colour")
    equal(statusCard.BackgroundColor3, STATUS_THEMES.success.background, "success status tints the card")
    equal(copyButton.Text, "Copy avatar", "copy button label restored")
    equal(copyButton.Active, true, "copy button re-enabled after a copy")
    equal(ENV.__clipboard, nil, "a successful preview does not touch the clipboard")

    -- Pose mirroring: change the live joint, fire RenderStepped, then compare.
    sourceNeck.Transform = { Angle = 42 }
    RunService.RenderStepped:Fire()
    local previewNeck = overlayNeck(preview)
    equal(previewNeck and previewNeck.Transform.Angle, 42, "overlay mirrors the live Motor6D pose")

    if resetButton then
        resetButton.MouseButton1Click:Fire()
        equal(overlayFolder(), nil, "reset destroys the overlay folder")
        equal(api.isPreviewing(), false, "API reports no preview after reset")
        equal(api.getTarget(), nil, "API clears the preview target after reset")
        equal(localRoot.LocalTransparencyModifier, 0, "reset restores the real character's visibility")
        equal(localFace.Transparency, 0, "reset restores decal visibility")
        equal(humanoid.DisplayDistanceType.Name, "Viewer", "reset restores the Humanoid display mode")
        contains(statusLabel.Text, "Back to your own avatar", "status confirms the reset")
        equal(statusDot.BackgroundColor3, COLORS.success, "reset uses the success status colour")
    end
end

-- API avatar: build a preview from the fetched description.
if input and copyButton and statusLabel and statusDot then
    advanceClock(2)
    local beforeDescriptionCreates = Players.DescriptionCreateCount
    input.Text = "TestUser"
    copyButton.MouseButton1Click:Fire()

    local preview = findPreview()
    check(preview ~= nil, "API username creates a preview")
    equal(Players.DescriptionCreateCount, beforeDescriptionCreates + 1, "preview used the description API")
    equal(Players.LastDescriptionRigType.Name, "R15", "description API used the local rig type")
    equal(api.getTarget() and api.getTarget().name, "TestUser", "API target name is resolved")
    equal(api.getTarget() and api.getTarget().userId, 12345, "API target ID is resolved")
    contains(statusLabel.Text, "Previewing TestUser (local only)", "status reports the API preview")
    equal(humanoid.ApplyCount, nil, "API preview never touches the real Humanoid")

    copyButton.MouseButton1Click:Fire()
    contains(statusLabel.Text, "Please wait a moment", "cooldown blocks an immediate re-copy")
    equal(statusDot.BackgroundColor3, COLORS.warning, "cooldown status uses the warning colour")

    if resetButton then
        resetButton.MouseButton1Click:Fire()
    end
end

-- Validation errors stay in the status card and do not create clipboard noise.
if input and copyButton and statusLabel and statusDot then
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

-- Fallback 1: API model creation fails, so clone the local rig and apply the
-- description to that client-created clone.
if input and copyButton and statusLabel and statusDot then
    advanceClock(2)
    local originalDescriptionCreate = Players.CreateHumanoidModelFromDescriptionAsync
    local originalUserIdCreate = Players.CreateHumanoidModelFromUserIdAsync
    Players.CreateHumanoidModelFromDescriptionAsync = function()
        error("forced description model failure")
    end
    Players.CreateHumanoidModelFromUserIdAsync = function()
        error("forced user-id model failure")
    end

    input.Text = "TestUser"
    copyButton.MouseButton1Click:Fire()

    local preview = findPreview()
    local previewHumanoid = preview and preview:FindFirstChildOfClass("Humanoid")
    check(preview ~= nil, "local clone fallback creates a preview")
    equal(previewHumanoid and previewHumanoid.ApplyCount, 1, "description is applied to the client-only clone")
    equal(previewHumanoid and previewHumanoid.Applied, apiDescription, "the clone receives the fetched description")
    equal(humanoid.ApplyCount, nil, "fallback still leaves the real Humanoid untouched")
    contains(statusLabel.Text, "Previewing TestUser (local only)", "fallback reports a successful preview")

    if resetButton then
        resetButton.MouseButton1Click:Fire()
    end

    Players.CreateHumanoidModelFromDescriptionAsync = originalDescriptionCreate
    Players.CreateHumanoidModelFromUserIdAsync = originalUserIdCreate
end

-- Fallback 2: ApplyDescription also fails, so copy the usable fields onto the
-- local clone and label it as a partial preview.
if input and copyButton and statusLabel and statusDot then
    advanceClock(2)
    local originalDescriptionCreate = Players.CreateHumanoidModelFromDescriptionAsync
    local originalUserIdCreate = Players.CreateHumanoidModelFromUserIdAsync
    Players.CreateHumanoidModelFromDescriptionAsync = function()
        error("forced description model failure")
    end
    Players.CreateHumanoidModelFromUserIdAsync = function()
        error("forced user-id model failure")
    end
    humanoid._denyApply = true

    input.Text = "TestUser"
    copyButton.MouseButton1Click:Fire()

    local preview = findPreview()
    local previewHumanoid = preview and preview:FindFirstChildOfClass("Humanoid")
    local bodyColors = preview and preview:FindFirstChild("BodyColors")
    local previewShirt = preview and preview:FindFirstChildOfClass("Shirt")
    check(preview ~= nil, "partial fallback creates a preview")
    equal(previewHumanoid and previewHumanoid.BodyHeightScale, 1.1, "partial fallback copies humanoid scale")
    check(bodyColors and bodyColors.HeadColor3 == apiDescription.HeadColor, "partial fallback copies body colours")
    contains(previewShirt and previewShirt.ShirtTemplate, "rbxassetid://111", "partial fallback copies clothing")
    contains(statusLabel.Text, "Partial preview of TestUser", "partial preview is labelled honestly")
    equal(statusDot.BackgroundColor3, COLORS.warning, "partial preview uses the warning colour")

    if resetButton then
        resetButton.MouseButton1Click:Fire()
    end

    humanoid._denyApply = nil
    Players.CreateHumanoidModelFromDescriptionAsync = originalDescriptionCreate
    Players.CreateHumanoidModelFromUserIdAsync = originalUserIdCreate
end

-- Every successful/validation path above should be warning-free.
equal(#warnings, 0, "no warnings during successful previews and validation")

-- A handled model-build failure must still be copied to the clipboard.
if input and copyButton and statusLabel and statusDot then
    advanceClock(2)
    local originalDescriptionCreate = Players.CreateHumanoidModelFromDescriptionAsync
    local originalUserIdCreate = Players.CreateHumanoidModelFromUserIdAsync
    Players.CreateHumanoidModelFromDescriptionAsync = function()
        error("forced description model failure")
    end
    Players.CreateHumanoidModelFromUserIdAsync = function()
        error("forced user-id model failure")
    end
    character.__failClone = true

    input.Text = "TestUser"
    copyButton.MouseButton1Click:Fire()

    local clipboard = ENV.__clipboard or ""
    contains(clipboard, "Avatar Copier v1.3.0 - error report", "build failure clipboard uses the current version")
    contains(clipboard, "Context: copy/build", "build failure clipboard includes the context")
    contains(clipboard, "Target: TestUser", "build failure clipboard includes the target")
    contains(clipboard, "Resolved user ID: 12345", "build failure clipboard includes the resolved ID")
    contains(clipboard, "Avatar source: avatar_api", "build failure clipboard includes the avatar source")
    contains(clipboard, "forced description model failure", "build failure clipboard includes attempt errors")
    contains(clipboard, "All local avatar preview methods failed.", "build failure clipboard includes the summary")
    contains(clipboard, "Traceback:", "build failure clipboard includes a traceback")
    contains(statusLabel.Text, "Error details copied to clipboard", "build failure tells the user about the clipboard")
    equal(statusDot.BackgroundColor3, COLORS.error, "build failure uses the error colour")
    equal(copyButton.Active, true, "controls recover after a build failure")

    character.__failClone = nil
    Players.CreateHumanoidModelFromDescriptionAsync = originalDescriptionCreate
    Players.CreateHumanoidModelFromUserIdAsync = originalUserIdCreate
end

-- Any unexpected Lua error must be copied to the executor clipboard.
if input and copyButton and statusLabel and statusDot then
    advanceClock(2)
    ENV.__clipboard = nil
    local originalGetPlayers = Players.GetPlayers
    Players.GetPlayers = function()
        error("intentional clipboard test failure")
    end

    input.Text = "ClipboardTest"
    copyButton.MouseButton1Click:Fire()
    Players.GetPlayers = originalGetPlayers

    local clipboard = ENV.__clipboard or ""
    contains(clipboard, "intentional clipboard test failure", "unexpected errors are copied to the clipboard")
    contains(clipboard, "Context: copy button", "clipboard report includes the failure context")
    contains(clipboard, "Traceback:", "clipboard report includes a traceback")
    contains(statusLabel.Text, "Unexpected error", "status explains that details were copied")
    equal(statusDot.BackgroundColor3, COLORS.error, "unexpected error uses the error status colour")
    equal(copyButton.Active, true, "controls recover after an unexpected error")

    local originalSetClipboard = ENV.setclipboard
    ENV.setclipboard = function()
        error("clipboard setter is broken")
    end
    local reportOk = pcall(reportError, "clipboard failure", "boom")
    ENV.setclipboard = originalSetClipboard
    equal(reportOk, true, "error reporting survives a broken clipboard")
end

-- Respawning while a preview is active cleans up the local overlay.
if input and copyButton and statusLabel then
    advanceClock(2)
    input.Text = "ServerFriend"
    copyButton.MouseButton1Click:Fire()
    check(api.isPreviewing(), "preview is active before the respawn event")

    LocalPlayer.CharacterAdded:Fire(character)
    equal(api.isPreviewing(), false, "CharacterAdded removes the stale overlay")
    equal(overlayFolder(), nil, "CharacterAdded removes the overlay folder")
    equal(localRoot.LocalTransparencyModifier, 0, "CharacterAdded restores character visibility")
    contains(statusLabel.Text, "Character respawned", "CharacterAdded asks the user to copy again")
end

-- Destroy must remove the overlay, restore the character, and clear globals.
if api and gui then
    advanceClock(2)
    if input and copyButton then
        input.Text = "ServerFriend"
        copyButton.MouseButton1Click:Fire()
        check(findPreview() ~= nil, "preview exists immediately before destroy")
    end

    api.destroy()
    equal(gui.Parent, nil, "destroy detaches the ScreenGui")
    equal(getgenv().AvatarCopier, nil, "destroy clears the global API")
    equal(getgenv().AvatarCopierCleanup, nil, "destroy clears the re-execution cleanup hook")
    equal(findPreview(), nil, "destroy removes the preview model")
    equal(overlayFolder(), nil, "destroy removes the overlay folder")
    equal(localRoot.LocalTransparencyModifier, 0, "destroy restores character visibility")
end

print(("%d checks, %d failed"):format(checks, failures))
if failures > 0 then
    error(("%d test(s) failed"):format(failures))
end
