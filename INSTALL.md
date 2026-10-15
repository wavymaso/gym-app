# Installing Gym on your Mac and iPhone

Gym isn't on the App Store. You build it yourself with Xcode, which is free. It takes about
20 minutes the first time and runs on your own devices, with your data staying on them.

## What you need
- A Mac with **macOS 15 or later** and **Xcode** (free, from the Mac App Store; 26 or later).
- An **Apple ID**. A free one works; see "Free vs paid Apple account" below.
- An **iPhone on iOS 18 or later** and a USB cable (optional: the Mac app works on its own).
- The **GitHub CLI** to fetch the food database: `brew install gh`, then `gh auth login`.

## 1. Get the code
```bash
git clone https://github.com/wavymaso/gym-app.git
cd gym-app
```
(The repository is private: ask for access first.)

## 2. Make it yours
Everyone needs their own Apple team and bundle ID.
1. Open Xcode → **Settings → Accounts → +** and sign in with your Apple ID. A "Personal Team" appears.
2. Find your **team ID**, a 10-character code. In Xcode open `Gym.xcodeproj` → target **Gym** → **Signing & Capabilities** → Team, pick yours, and the ID shows in the build settings as `DEVELOPMENT_TEAM`. With a paid account it's also on developer.apple.com → Membership.
3. Run, with your own team ID and a unique bundle ID:
```bash
tools/configure.sh ABCDE12345 com.yourname.gym
```

## 3. The offline food database
```bash
tools/get-food-db.sh          # downloads Gym/foods.sqlite (~50 MB)
```
Or build it from scratch with `tools/update-food-db.sh` (1,3 GB download, about 25 minutes).
It holds Open Food Facts products for Spain, Saudi Arabia and the Gulf (ODbL) and USDA generic foods (public domain).

## 4. Install on the Mac
```bash
tools/install-mac.sh
```
This builds the app, backs up any existing data, and puts Gym in /Applications. Open it and
follow the setup: units, body, goal. First launch takes a few seconds.

## 5. Install on the iPhone
1. Plug the iPhone into the Mac, unlock it and tap **Trust**.
2. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
3. On the Mac:
```bash
tools/install-phone.sh
```
4. The first time only: on the iPhone, open **Settings → General → VPN & Device Management**,
   tap your Apple ID and choose **Trust**.

With more than one iPhone connected, choose one: `GYM_PHONE=<UDID> tools/install-phone.sh`
(`xcrun devicectl list devices` shows the UDIDs).

### Free vs paid Apple account
- **Free:** the app works for **7 days**, then has to be reinstalled. Plug in and run
  `tools/install-phone.sh` again; your data stays. Gym shows a banner on the dashboard two days before.
- **Paid** (99 €/year): installs last a year, and TestFlight is possible.

## 6. Optional extras

### Sync between Mac and iPhone (Tailscale)
Your phone and Mac sync directly with each other; nothing goes through a server.
1. Install **Tailscale** on both (free, tailscale.com) and sign in with the same account.
2. On the Mac, publish Gym's sync port to your own devices only:
```bash
tailscale serve --bg --https=8443 http://127.0.0.1:8010
```
3. Mac app: **More → Integrations → iPhone sync → On**. It shows an address and a pairing code.
4. iPhone app: **More → Integrations → Connect to your Mac** and enter both.

### Photo logging with AI
- **On the Mac, free and private:** `brew install ollama`, then `ollama pull qwen3-vl:4b-instruct`.
  With sync set up, the phone uses the Mac's model too.
- **Gemini**, as a fallback or on its own: get a free key at aistudio.google.com → **More → Photo logging**
  → paste the key. The free tier lets Google use what you send.

### Food search
USDA search works with a shared demo key. For unlimited searches, get a free key at
api.data.gov and add it under **More → Food search**.

### Apple Health
**More → Integrations**: weigh-ins, steps and sleep from Apple Health (iPhone).

## Updating
```bash
git pull
tools/install-mac.sh
tools/install-phone.sh
```
Before an update changes how data is stored, Gym copies your database aside automatically, and it
keeps daily backups (More → Backups). For extra safety, choose an iCloud Drive folder there.

## Troubleshooting
| Problem | Fix |
|---|---|
| "No iPhone found" | Unlock it, plug it in, tap Trust, and check Developer Mode is on |
| "Untrusted developer" on the phone | Settings → General → VPN & Device Management → Trust |
| Signing errors in the build | Run `tools/configure.sh` again with your team ID; pick a bundle ID nobody else uses |
| The app stopped opening after a week | Free signing ran out: `tools/install-phone.sh` |
| Phone can't reach the Mac | Tailscale on in both; Gym open on the Mac; `tailscale serve status` shows port 8443 |
| Something looks wrong with your data | More → Diagnostics: integrity check, recent problems, export to share |

For developers: `ARCHITECTURE.md` explains the code; `tools/check.sh` builds and tests everything.
