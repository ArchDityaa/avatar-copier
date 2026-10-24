# Avatar Copier

> A **fully client-side** Roblox avatar copier for **Delta Executor** — preview any player's avatar on your own character, without changing anything for anyone else.

![Roblox](https://img.shields.io/badge/Roblox-Client--side-6366f1)
![Executor](https://img.shields.io/badge/Executor-Delta-6366f1)
![License](https://img.shields.io/badge/License-MIT-4ade80)

---

## What it does

Type a **username**, **user ID**, or **Roblox profile URL** into the small draggable window and press **Copy**. The script fetches that user's `HumanoidDescription` and applies it to your own character **locally**.

Because character appearance changes made from the client are never replicated to the server, **only you see the new avatar**. Other players still see your normal look. No server state is touched, nothing is sent anywhere, and no player is affected.

| Feature | Notes |
| --- | --- |
| Copy by username | `Roblox` |
| Copy by user ID | `1` |
| Copy by profile URL | `https://www.roblox.com/users/1/profile` |
| In-server fast path | Instantly reuses the target's live description when they are in the same server |
| Reset button | Restores your original appearance |
| Draggable GUI | Minimal dark window, stays out of the way |

---

## Requirements

- Roblox client (PC, or any platform where Delta runs)
- [Delta Executor](https://deltaexploit.com/) or any executor with `game:HttpGet` (`gethui` is optional — see [Troubleshooting](#troubleshooting))
- An R15 avatar is recommended (most modern games); see [Limitations](#limitations)

---

## Installation

### Option A — Paste the source

1. Open Delta Executor and attach it to Roblox.
2. Open [`src/CopyAvatar.lua`](src/CopyAvatar.lua), copy the whole file.
3. Paste it into the executor and press **Execute**.

### Option B — Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ArchDityaa/avatar-copier/main/src/CopyAvatar.lua"))()
```

If `raw.githubusercontent.com` is slow or blocked, use the jsDelivr mirror:

```lua
loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/ArchDityaa/avatar-copier@main/src/CopyAvatar.lua"))()
```

---

## Usage

1. A small window titled **Avatar Copier** appears on screen.
2. Enter a username, user ID, or profile URL.
3. Press **Copy** (or hit `Enter`).
4. Wait for the status line: `Copied from <name> (local only)`.
5. Press **Reset** to go back to your own avatar, or close the window with `×`.

### Programmatic API

The script exposes a small API through `getgenv()`:

```lua
AvatarCopier.copy("Roblox")    -- copy by username / ID / URL
AvatarCopier.reset()           -- restore your original look
AvatarCopier.destroy()         -- close the window
AvatarCopier.version           -- "1.0.1"
```

---

## How it works

1. **Resolve the target**
   - If the user is in the same server, their live `Humanoid:GetAppliedDescription()` is reused — instant and API-free.
   - Otherwise the script calls `Players:GetUserIdFromNameAsync` (for usernames) and then `Players:GetHumanoidDescriptionFromUserIdAsync`.
2. **Apply locally**
   - The description is applied to *your* `Humanoid` with `ApplyDescriptionAsync` (with safe fallbacks to older variants).
   - Client-side appearance changes are never replicated, so other players are unaffected.
3. **Restore**
   - The first time you copy, your original description is snapshotted. **Reset** re-applies it.

Only `Players`, `UserInputService`, and `TweenService` are used. There is no HTTP call to any third-party service, no webhook, and no data collection.

---

## Limitations

- **R6 games / R6 avatars** — mesh and accessory parts may not map perfectly; body colors and clothing usually do.
- **Custom avatar systems** — games that overwrite `HumanoidDescription` on spawn or render avatars through their own system may revert your change.
- **Private / moderated avatars** — Roblox may refuse to return a description; the status line will say the avatar could not be loaded.
- **Rate limits** — repeated lookups can be throttled by Roblox. The script enforces a short cooldown; if you still get throttled, wait a few seconds.
- **Respawn / rejoin** — local appearance resets, just run the script again.
- **Other players' view** — by design, they never see the copied avatar. This tool is a personal preview, not a disguise.

---

## Development

The script is tested headlessly with open-source tooling — no Roblox client required.

| Tool | Purpose |
| --- | --- |
| [Luau](https://github.com/luau-lang/luau) | Official Roblox Lua compiler/runtime. Compiles the script and executes the mock harness. |
| [Selene](https://github.com/Kampfkarren/selene) | Static analysis against the Roblox standard library plus the executor globals. |

```bash
./tests/run.sh
```

`tests/mock_roblox.luau` implements only the Roblox API surface this script uses (instances, signals, services, `HumanoidDescription`, `gethui`). `tests/spec.luau` then asserts the behaviour that matters:

- the window is parented to the `ScreenGui` (the v1.0.0 regression),
- mobile attaches to `PlayerGui`, desktop prefers `gethui`,
- the in-server fast path and the username API path,
- cooldown, unknown user, empty input, reset, and cleanup,
- no warnings on the happy path.

The suite runs twice, with a mobile and a desktop profile. CI runs the same script on every push.

Point the runner at locally installed binaries if they are not on `PATH`:

```bash
LUAU=/path/to/luau \
LUAU_COMPILE=/path/to/luau-compile \
SELENE=/path/to/selene \
./tests/run.sh
```

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Window does not appear | Check the console: it should print `[Avatar Copier] GUI attached to <parent>`. If it says `Could not attach the GUI`, pin a container before running: `getgenv().AVATAR_COPIER_PARENT = "PlayerGui"` (or `"CoreGui"` / `"gethui"`). |
| Window appears but is empty | That was a v1.0.0 bug (the panel was never parented to the ScreenGui). Rerun the loadstring above to get v1.0.1. |
| `Player not found` | Check the exact spelling, or use the numeric user ID / profile URL. |
| `Could not load that avatar` | Usually a rate limit or a private avatar. Wait a few seconds and retry. |
| `Failed to apply` | The game's avatar setup may be incompatible (e.g. custom character). Try another avatar or rejoin. |
| Nothing changes on my character | Make sure your character is loaded, then retry. In R6 games, expect partial results. |

---

## Disclaimer

This project is provided for **personal, educational, and creative use** on your own client. It does **not** modify the game server, other players, or any game state, and it grants no advantage.

Using third-party executors may violate the [Roblox Terms of Use](https://en.help.roblox.com/hc/en-us/articles/115004647846) and can lead to account action. You use this script **at your own risk** and are solely responsible for your account.

This project is **not affiliated with, endorsed by, or sponsored by** Roblox Corporation or Delta Executor.

Read the full [DISCLAIMER.md](DISCLAIMER.md) before use.

---

## License

[MIT](LICENSE) © 2026 ArchDityaa

---

## Contributing

Issues and pull requests are welcome. Keep changes client-side only: nothing in this project should ever modify server state or affect other players.
