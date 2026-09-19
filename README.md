<p align="center">
  <img src="docs/icon.png" width="128" alt="UP! logo">
</p>

<h1 align="center">UP!</h1>

<p align="center">
  <b>A native macOS companion for League of Legends that tries to win the game in champ select.</b><br>
  Pick advice, counters, bans, runes and builds, match history, player scouting and client automation, in one dark, fast, native app.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0F1729?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-3987E5?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-3987E5">
  <img alt="10 languages" src="https://img.shields.io/badge/languages-10-3987E5">
  <img alt="No memory reading" src="https://img.shields.io/badge/memory%20reading-none-2FBF71">
</p>

---

## Contents

- [Features](#features)
- [Fair play and safety](#fair-play-and-safety)
- [Requirements](#requirements)
- [Install and run](#install-and-run)
- [Using UP!](#using-up)
- [Where the data comes from](#where-the-data-comes-from)
- [How the pick score works](#how-the-pick-score-works)
- [Project structure](#project-structure)
- [Translations](#translations)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Legal](#legal)

---

## Features

### 🎯 Champ select assistant
A dedicated window opens by itself when champ select starts and closes when it ends. It changes as the draft goes on.

| Stage | What you see |
|---|---|
| **Planning** | **Best picks for you**: the top 8 champions you own for your role, each with a 0–99 fit score and the reasons behind it ("Beats Zed 55 %", "Weak vs Malphite 43 %", "Mastery 120k", "Adds magic damage your team lacks"). You can switch role in one click. <br>**Ban suggestions**: champions that beat your best pick and the strongest threats in your lane. <br>**Team composition**: magic vs physical damage, frontline, crowd control and mobility for both teams, with warnings such as "little frontline" or "enemy is physical-heavy". |
| **Hover** | Your hovered champion loads by itself: its top rune pages from op.gg (Emerald+), **Master+** and Riot, each imported with one click, and its win rate against every enemy revealed so far. |
| **Lock-in** | A **game plan** (does the champion scale or spike early, how to play the lane matchup, skill max order, core items) and the full build broken down by **Emerald+ / Master+ / Challenger**. Runes, summoner spells and an item set are pushed into the client. |

The left rail shows your teammates' rank, recent form and tags, the enemy picks with your lane opponent highlighted, the bans, and your own form.

### ⚡ Automation
- **Auto-accept** match found, with a configurable delay and sound and Dock alerts.
- **Rune import** on lock-in (or on hover), from the source you choose: most winning (Emerald+), high elo (Master+) or Riot's recommendation.
- **Summoner spells**, with Flash kept on D or F as you prefer.
- **Item sets** written into the client (starter, boots, core, alternatives, late game).
- Optional **Play again** after each game.

### 📚 Builds, runes and tier list
- Every champion and role: runes, spells, starting items, boots, core builds, late items, skill order, hardest and easiest matchups, win rate by game length, and win rate across the last 10 patches.
- Champion profile: roles, damage type, difficulty, playstyle ratings, and every ability with its cooldown and cost per rank.
- Tier list per role with win, pick and ban rates and the rank change since the last patch.

### 👥 Players
- **Overview**: rank, recent win rate, today's session, KDA, CS/min, damage/min, vision/min, recent matches, mastery and most played champions.
- **Match grades**: every recent match gets a grade from **S+** to **D**, your place in the lobby (**MVP**, **ACE**) and badges such as Perfect KDA, Pentakill, Legendary or Top damage. The grade compares your KDA, kill participation, damage, deaths, farm, vision and objectives with everyone else in the same match.
- **Match history** (**Overview → All matches**): a summary of your average grade, MVP games, best game and badges, then every recent match. Click a match to see all players with their grades, KP, damage and gold charts, bans and objectives.
- **Player profiles** for anyone on any server (EUNE, EUW, NA, KR and 13 more), opened from the search bar: rank, recent form, the last 20 matches with grades and every player of each match, and the champions they play in ranked this season.
- **Scout tags**: win and loss streaks, possible smurf, one-trick, strong in ranked, dies a lot, inactive and more.

### 🎮 In-game HUD
A HUD appears over the game by itself as soon as the match loads. It is shown **only while League of Legends is the frontmost app**, never over other apps. With several monitors it always appears on the monitor the game is on, and follows the game if you move it. Clicking the HUD itself or the desktop doesn't hide it. It's a small card you can drag anywhere, and **×** hides it.

The mini HUD is compact (about 250 × 300 pt) and shows only what matters mid-fight:
- **Header**: clock, kills and the item-gold difference.
- **Objectives**:
  - dragon (including Elder) and Baron timers from game events,
  - inhibitor respawns labelled by side ("Our mid inhibitor" in blue, "Enemy top inhibitor" in red).

  Timers are rebuilt from event history after a reconnect.
- **Enemies**: level, K/D/A, respawn timer while dead, and **every item they hold**, including small components. Counter items such as Zhonya's, Guardian Angel, QSS and anti-heal are outlined in red.
- **You**: the next core item with the gold still missing, and your CS per minute.
- **Alerts**:
  - your lane opponent or the enemy jungler reaching 6, 11 or 16,
  - enemy item completions,
  - the enemy jungler dying ("invade or take an objective"),
  - 3+ enemies dead,
  - an objective spawning in under a minute,
  - soul point,
  - aces and Barons,
  - "you can buy X now".
- **Match overview** (<kbd>⇧</kbd><kbd>Tab</kbd> or the expand button): the HUD turns into a large overview of both teams, centred at the top of the screen. It shows team average rank and form, and for every player:
  - rank, ranked games and win rate,
  - how well they know their champion (Main / Veteran / Experienced / Played before / First time?), with mastery level and points and their recent games and win rate on it,
  - last 5 results, average KDA and scout tags,
  - live K/D/A, CS and items.

  Below the teams:
  - **Your build path**: items you own ticked off, the next item highlighted with the gold still missing, and the skill max order.
  - **Itemize vs enemy**: the enemy's magic/physical damage split and counter items picked for your champion type. Examples: anti-heal vs healers, magic resist vs AP teams, armor or stasis vs AD teams, Mercury's or QSS vs crowd control, penetration vs tanks, Serpent's Fang vs shields.
  - **Lane & threats**: your lane opponent with the matchup win rate and a tip, plus enemies who are fed, levels ahead or holding counter items.

  Press <kbd>⇧</kbd><kbd>Tab</kbd> again (or ×) to return to the HUD at its old position. The overview can be dragged too and reopens where you left it. If you closed the mini HUD with ×, it stays closed: the overview still opens with <kbd>⇧</kbd><kbd>Tab</kbd>, and its **Mini HUD** button (or <kbd>⌃</kbd><kbd>⇧</kbd><kbd>H</kbd>) brings the mini HUD back. <kbd>⇧</kbd><kbd>Tab</kbd> is only captured while the game is in front, so it keeps working normally in other apps.
- Controls:
  - drag the card to move it (the position is remembered and the HUD returns there after the match overview),
  - drag the corner grip to resize it (70–180 %),
  - × hides it and <kbd>⌃</kbd><kbd>⇧</kbd><kbd>H</kbd> brings it back,
  - there is a compact mode (timers only),
  - use windowed or borderless mode in the game.
- **Preview** it without playing: **Tools → Preview in-game HUD** or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>G</kbd> runs a scripted one-minute game with sample players in a normal window, including the match overview.

**Not included, on purpose:** ally or enemy summoner and ultimate cooldowns, and timers for every jungle camp. The Live Client API does not expose them, so they could only come from reading game memory or the screen. Riot's policy forbids that ("…e.g. automatically or manually allowing tracking enemy ultimate cooldowns") and Vanguard bans it. Allies' cooldowns and your own camps' respawns are already shown by the game itself.

### 🔎 Search everywhere
The search field sits in the top bar on every page and widens when you use it (<kbd>⌘</kbd><kbd>K</kbd>). The server picker on its left (for example **EUNE**) decides where players are looked up; it starts on your client's server. It suggests as you type:
- **Champions**: opens their build.
- **Players**: you, your friends, recent searches and recent teammates, or any `Name#TAG` to look up.
- **Accounts on the server**: every account with that name, for example all the "faker" accounts on EUNE, with level, solo rank and a badge for pro players. Scroll down and more keep loading.
- **#tags**:
  - `#top` `#jungle` `#mid` `#adc` `#support` open the tier list for that role,
  - `#assassins` `#fighters` `#mages` `#marksmen` `#tanks` `#supports` filter champions by class,
  - `#tierlist` `#builds` `#history` `#tools` `#overview` `#me` `#settings` `#preview` `#hud` are shortcuts.

Use <kbd>↑</kbd><kbd>↓</kbd> to move, <kbd>↩</kbd> to open and <kbd>esc</kbd> to close.

### 🛠 Tools
Create a lobby for any queue, start or cancel matchmaking, accept, play again, skip post-game stats, reconnect, set your status message and availability, delete UP!'s rune pages, and restart a frozen client UI.

### 🌍 10 languages
English · Deutsch · Français · Español · Italiano · Português · Nederlands · Polski · Čeština · Slovenčina. You can switch at any time from the flag in the top bar, the **Language** menu or Settings. Numbers follow the selected language (for example `51,2 %`).

---

## Fair play and safety

UP! only talks to **interfaces Riot's own software exposes**:

- the League client's local API (LCU), the same API the client uses for its own UI (widely used by companion apps, but not officially supported, so endpoints can change with client patches),
- Riot's **Live Client Data API** during a game,
- public build and player statistics (op.gg) and static game assets.

It **never reads or writes game memory**, injects into the game or touches Vanguard. Every automation is something you could do by hand in the client (accept a match, set runes, spells and item sets). UP! does **not** auto-pick, auto-ban, reveal hidden names in ranked champ select, dodge, or show information the game hides from you (such as enemy summoner or jungle timers).

> Riot's policies can change. Check the [Riot Developer Portal](https://developer.riotgames.com/policies/general) before distributing builds.

---

## Requirements

- macOS 14 Sonoma or later (Apple Silicon or Intel)
- Xcode 16+ or a Swift 6 toolchain (`swift --version`)
- The League of Legends client installed and logged in

---

## Install and run

```bash
git clone https://github.com/<your-account>/UP.git
cd UP
./scripts/build-app.sh      # release build → dist/UP!.app (ad-hoc signed)
open "dist/UP!.app"
```

For development:

```bash
swift build
.build/debug/UP             # runs the app directly
```

The build is ad-hoc signed. On another Mac, the first launch may need a right-click on the app and **Open**, or `xattr -dr com.apple.quarantine "UP!.app"`.

---

## Using UP!

1. Start the League client. UP! finds it on its own through the client's lockfile or process arguments; the dot on your profile picture turns green.
2. Queue up. UP! accepts the match if auto-accept is on.
3. Switch sections with <kbd>⌘</kbd><kbd>1</kbd>–<kbd>⌘</kbd><kbd>4</kbd> or the navigation, or jump anywhere with the search bar (<kbd>⌘</kbd><kbd>K</kbd>). The navigation sits in the top bar as **tabs** next to the logo by default; it also comes as **League-style tabs**, a **side rail**, a **floating dock** at the bottom and a **compact side pill**. Pick one in Settings or the profile menu, or press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>N</kbd> to flip through them. During champ select every style shows a live **Champ select** button that brings the assistant back.
4. Champ select opens the assistant window. Hover or lock a champion to get runes, a build and the game plan.
5. After the game, **Overview → Recent matches** grades how you played. Results of actions (imported runes, saved item sets, lobby commands) show up as short messages at the bottom of the window.

### Try it without a game
**Tools → Preview champ select** (or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>P</kbd>) opens the assistant with a sample draft. Step through **Hover top pick → Lock in (preview)**. Nothing is sent to the client in preview mode.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd><kbd>1</kbd> – <kbd>⌘</kbd><kbd>4</kbd> | Overview, Builds & runes, Tier list, Tools |
| <kbd>⌘</kbd><kbd>[</kbd> | Back from match history or a player profile |
| <kbd>⌘</kbd><kbd>K</kbd> | Search champions, players and #tags |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>N</kbd> | Next navigation style |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>D</kbd> | Open the champ select window |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>P</kbd> | Preview champ select |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>A</kbd> | Accept the match |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>G</kbd> | Preview the in-game HUD |
| <kbd>⌃</kbd><kbd>⇧</kbd><kbd>H</kbd> | Show or hide the HUD (global, works in game) |
| <kbd>⇧</kbd><kbd>Tab</kbd> | Switch between the HUD and the match overview (only while the game is in front) |
| <kbd>⌘</kbd><kbd>,</kbd> | Settings |

The **UP!** item in the macOS menu bar has two commands: **Open UP!** and **Quit UP!**.

### Settings

| Setting | Default |
|---|---|
| Accept matches automatically (delay 0–8 s) | On, 2 s |
| Open the champ select window automatically | On |
| Import runes automatically, source | On, Emerald+ |
| Import on hover instead of lock-in | Off |
| Overwrite the current page when none is free | On |
| Set summoner spells, Flash on F | On, On |
| Save item sets | On |
| Scout teammates | On |
| In-game HUD (shown only while the game is in front) | On |
| Compact HUD (timers only), pop-up alerts | Off, On |
| Play again after each game | Off |

Rune pages created by UP! are named with the `UP!` prefix, so they are easy to find and delete (**Tools → Delete "UP!" rune pages**).

---

## Where the data comes from

| Source | Used for | Key needed |
|---|---|---|
| **LCU** `https://127.0.0.1:<port>` | Summoner, ranked, match history, mastery, champ select session, owned champions, runes, spells, item sets, lobby, chat | No (local lockfile token) |
| **LCU WebSocket** (`OnJsonApiEvent_…`) | Live gameflow phase, ready check and champ select updates | No |
| **Live Client Data API** `https://127.0.0.1:2999` | In-game players, items, scores, events and timers | No |
| **op.gg champion API** | Build stats per role and elo (Emerald+, Master+, Challenger), counters, tier list, game length and patch trends | No (unofficial, may change) |
| **op.gg summoner API** | Account search by name on every server, and rank, season champions and the last 20 matches of players on other servers | No (unofficial, may change) |
| **Riot recommended pages** (LCU `/lol-perks/v1/recommended-pages`) | Fallback runes and spells | No |
| **Client game data and CommunityDragon** | Champion, item, rune and spell names, icons, splash art, abilities, rank emblems | No |

UP! does not need a Riot API key and runs entirely on your machine. Results are cached briefly: builds and player profiles for 5 minutes and the tier list for 10.

---

## How the pick score works

Each candidate is a champion you own (or free to play) that is viable in your role, plus your comfort picks. Every candidate starts at 50, and then:

- **Meta**: ± role win rate, plus a bonus for S and A tier.
- **Counters**: the win rate against every revealed enemy, with your lane opponent weighted most.
- **You**: your recent win rate on the champion (3+ games) and your mastery points. Brand-new champions get a small penalty.
- **Team fit**: a bonus when the champion adds the damage type your team lacks.

The result is clamped to 0–99 and shown with the strongest reasons. It's a guide, not a rule. Comfort and communication still win games.

---

## Project structure

```
UP/
├── Package.swift                 Swift package (single executable target "UP")
├── Sources/UP/
│   ├── App.swift                 App entry, main window, page routing, menus
│   ├── Core/                     LCU client + WebSocket, lockfile, Live Client API,
│   │                             models, static game data, localization
│   ├── Features/                 AppModel (coordinator), DraftAdvisor, HUDState, Search, BuildService,
│   │                             ClientActions, PlayerScout, PlayerSearch (servers, op.gg accounts), Performance (match grades),
│   │                             LiveGameAnalyzer, MatchInsights, HUDPreview, Settings, SelfTest
│   ├── UI/                       Theme (design tokens), components, charts, screens, match cards,
│   │                             top bar + search, navigation styles, logo, champ select window, in-game HUD
│   └── Translations/             Generated L10n+<lang>.swift tables
├── Translations/                 keys.json + <lang>.json (source of truth)
├── Resources/AppIcon.icns        App icon
├── scripts/
│   ├── build-app.sh              Release build → dist/UP!.app
│   ├── make-icon.sh              Renders the app icon (make-icon/main.swift + UI/Logo.swift)
│   ├── extract-keys.py           Lists untranslated strings (--prune drops unused ones)
│   └── gen-translations.py       Validates JSON, generates Swift tables
└── docs/                         README assets
```

---

## Translations

English strings in code are the lookup keys: `tr("Your turn to pick")`, `tr("%d games today", n)`.

```bash
python3 scripts/extract-keys.py      # prints strings missing from Translations/keys.json (--prune removes unused keys)
# add them to keys.json and translate them in Translations/<lang>.json
python3 scripts/gen-translations.py  # validates format specifiers, writes Swift tables
```

The generator fails if a translation is missing or its format specifiers (`%@`, `%d`, `%.1f`, `%%`) don't match the English key. To add a language, add a case to `AppLanguage` in `Core/Localization.swift`, register its table in `Localizer.tables`, and add `Translations/<code>.json`.

---

## Development

```bash
swift build                         # debug build
.build/debug/UP --selftest          # read-only smoke test against the running client
./scripts/build-app.sh              # release app bundle
./scripts/make-icon.sh              # re-render the app icon and docs/icon.png
```

`--selftest` checks the client connection, summoner, game data, profile and history, lookup, mastery, match detail, op.gg builds (ranked, ARAM, main role), champion details, Riot runes, the tier list, op.gg account search and profiles, and the WebSocket. It changes nothing on your account.

Design tokens (colors, radii, typography) live in `UI/Theme.swift`. Data colors were validated for colour-blind separation on the panel surface.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Looking for client…" | Start and log into the League client. UP! retries every 3 seconds. |
| Runes don't import: "No free rune page" | Enable **Overwrite the current page** in Settings, or delete a page. |
| Builds show "op.gg returned no data" | op.gg may be down or have changed its API. Riot's recommended runes still work. |
| The HUD isn't visible over the game | Use windowed or borderless mode (macOS can't draw over exclusive fullscreen), make sure the game (not the client) is in front, check **Settings → In-game HUD**, and press <kbd>⌃</kbd><kbd>⇧</kbd><kbd>H</kbd> in case you hid it with ×. |
| "UP!" can't be opened because Apple cannot check it | Right-click the app and choose **Open**, or clear the quarantine flag (see above). |

---

## Roadmap

- [ ] Windows version (the LCU and Live Client parts are portable)
- [ ] Pro player builds when a reliable public source exists
- [ ] Post-game report with lane and gold graphs
- [ ] ARAM bench helper
- [ ] Sparkle auto-updates and a notarized release

---

## Legal

UP! isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, League of Legends and all associated properties are trademarks or registered trademarks of Riot Games, Inc.

Build statistics, account search and profiles on other servers are provided by op.gg. UP! isn't affiliated with op.gg.

**License:** not chosen yet. Until a `LICENSE` file is added, all rights are reserved.
