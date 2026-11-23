<p align="center">
  <a href="https://github.com/SpotX-Official/SpotX/releases"><img src=".github/Pic/logo.png" /></a>
</p>

<p align="center">
  <a href="https://t.me/spotify_windows_mod"><img src="https://spotx-official.github.io/images/shields/SpotX_Channel.svg"></a>
  <a href="https://t.me/SpotxCommunity"><img src="https://spotx-official.github.io/images/shields/SpotX_Community.svg"></a>
  <a href="https://github.com/SpotX-Official/SpotX-Bash"><img src="https://spotx-official.github.io/images/shields/SpotX_for_Mac&Linux.svg"></a>
  <a href="https://telegra.ph/SpotX-FAQ-09-19"><img src="https://spotx-official.github.io/images/shields/faq.svg"></a>
</p>

<h2> 
  <div align="center">
    <b>Patcher for Spotify Desktop Client on Windows &amp; macOS (Apple Silicon / Intel)</b>
  </div> 
</h2>

<p align="center"> •
  <a href="#requirements">Requirements</a> •
  <a href="#features">Features</a> •
  <a href="#installation--update">Installation (Windows)</a> •
  <a href="#macos-installation">Installation (macOS)</a> •
  <a href="#uninstall">Uninstall</a> •
  <a href="#faq">FAQ</a> •
  <a href="#disclaimer">Disclaimer</a>
</p>

<h1 id="requirements">Requirements</h1>

**Windows:**
- **OS:** Windows 7-11
- **Spotify:** [Official desktop version](https://loadspot.vercel.app/) (Microsoft Store version is not suitable)
- **PowerShell:** 5.1 and above

**macOS (Apple Silicon M-series / Intel):**
- **OS:** macOS 11 Big Sur or later
- **Spotify:** [Official macOS desktop version](https://www.spotify.com/download/mac/) (not Mac App Store)
- **Tools:** `bash`, `python3`, `curl`, `zip`, `unzip`, `codesign` — all pre-installed on modern macOS

<h1 id="features">Features</h1>

- **Blocks all banner, video, and audio ads** in the client
- **Hiding podcasts, episodes, and audiobooks** from the homepage (optional)
- **Block Spotify automatic updates** (optional)
- **Some native experimental features have been changed**
- **Analytics sending has been disabled** 
- **Advanced installation [parameters](https://github.com/SpotX-Official/SpotX/discussions/60)**
- **🍎 Native macOS support** — Apple Silicon (M1/M2/M3/M4) and Intel, with ad-hoc re-signing

<h1 id="installation--update">Installation / Update</h1>
<h3>Choose installation type:</h3>
<details>
<summary><small>Usual installation (New theme)</small></summary><p>
  
  #### During installation, you need to confirm some actions, also contains:
  
  - New theme activated (new right and left sidebar, some cover change)
  - All [experimental features](https://github.com/SpotX-Official/SpotX/discussions/50) included

  <h4> </h4>
  
#### Just download and run [Install_New_theme.bat](https://raw.githack.com/amd64fox/SpotX/main/Install_New_theme.bat)

or

#### Run The following command in PowerShell:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.ps1') } -new_theme"
```

#### mirror

```ps1
iex "& { $(iwr -useb 'https://spotx-official.github.io/SpotX/run.ps1') } -m -new_theme"
```

</details>
  

<details>
<summary><small>Usual installation (Old theme)</small></summary><p>
  
  #### During installation, you need to confirm some actions, also contains:
  - Forced installation of version 1.2.13 (since the old theme was removed in subsequent versions)
  - Old theme activated
  - Automatic blocking of Spotify updates
  - All [experimental features](https://github.com/SpotX-Official/SpotX/discussions/50) included

  <h4> </h4>
  
#### Just download and run [Install_Old_theme.bat](https://raw.githack.com/amd64fox/SpotX/main/Install_Old_theme.bat)

or

#### Run The following command in PowerShell:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.ps1') } -v 1.2.13.661.ga588f749 -confirm_spoti_recomended_over -block_update_on"
```

#### mirror

```ps1
iex "& { $(iwr -useb 'https://spotx-official.github.io/SpotX/run.ps1') } -m -v 1.2.13.661.ga588f749 -confirm_spoti_recomended_over -block_update_on"
```

</details>
 
<details>
<summary><small>Full installation</small></summary><p>
  
  <h4>Full installation without confirmation, what does it do?</h4> 
  
  - New theme activated (new right and left sidebar, some cover change)
  - Hiding podcasts/episodes/audiobooks from the homepage
  - Activated [static theme](https://github.com/SpotX-Official/SpotX/discussions/50#discussioncomment-4096066) <kbd>spotify</kbd> for lyrics
  - Hiding [ad-like sections](https://github.com/SpotX-Official/SpotX/discussions/50#discussioncomment-4478943)
  - All [experimental features](https://github.com/SpotX-Official/SpotX/discussions/50) included
  - Removal of Spotify MS if it was found 
  - Installation of the recommended version of Spotify (if another client has already been found, it will be installed over) 
  - Blocking of Spotify updates
  - After the installation is completed, the client will autorun.
  
<h4> </h4>

#### Just download and run [Install_Auto.bat](https://raw.githack.com/amd64fox/SpotX/main/scripts/Install_Auto.bat)

or

#### Run The following command in PowerShell:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.ps1') } -confirm_uninstall_ms_spoti -confirm_spoti_recomended_over -podcasts_off -block_update_on -start_spoti -new_theme -adsections_off -lyrics_stat spotify"
```

#### mirror

```ps1
iex "& { $(iwr -useb 'https://spotx-official.github.io/SpotX/run.ps1') } -m -confirm_uninstall_ms_spoti -confirm_spoti_recomended_over -podcasts_off -block_update_on -start_spoti -new_theme -adsections_off -lyrics_stat spotify"
```

</details>

<details>
<summary><small>Other types of installations</summary><p>

<details>
<summary><small>Installation for premium</small></summary><p>
  
  #### Usual installation only without ad blocking, for those who have a premium account, also contains:
  
  - New theme activated (new right and left sidebar, some cover change)
  - Disabled only audio ads in podcasts
  - All [experimental features](https://github.com/SpotX-Official/SpotX/discussions/50) included

  <h4> </h4>
  
#### Just download and run [Install_Prem.bat](https://raw.githack.com/amd64fox/SpotX/main/scripts/Install_Prem.bat)

or

#### Run The following command in PowerShell:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.ps1') } -premium -new_theme"
```

#### mirror

```ps1
iex "& { $(iwr -useb 'https://spotx-official.github.io/SpotX/run.ps1') } -m -premium -new_theme"
```

</details>

<details>
<summary><small>Installing with parameters</small></summary><p>

You can specify various parameters for a more flexible installation, more [details here](https://github.com/SpotX-Official/SpotX/discussions/60)

</details>

</details>

<h1 id="uninstall">Uninstall</h1>

**Windows:**
- Just run [Uninstall.bat](https://raw.githack.com/amd64fox/SpotX/main/Uninstall.bat)

or

- Reinstall Spotify ([Full uninstall Spotify](https://github.com/amd64fox/Uninstall-Spotify) recommended)

**macOS:**
```bash
# Restore the original xpui.spa from backup
cp "/Applications/Spotify.app/Contents/Resources/Apps/xpui.spa.bak" \
   "/Applications/Spotify.app/Contents/Resources/Apps/xpui.spa"
# Re-sign (required after restoring)
codesign --force --deep --sign - "/Applications/Spotify.app"
```
Or simply reinstall Spotify from the [official website](https://www.spotify.com/download/mac/).

<h1 id="macos-installation">🍎 macOS Installation (Apple Silicon &amp; Intel)</h1>

<h3>Requirements</h3>

- macOS 11 Big Sur or later (Apple Silicon M1/M2/M3/M4 or Intel)
- Spotify desktop app (from [spotify.com/download/mac](https://www.spotify.com/download/mac/), **not** the Mac App Store)
- All required tools (`bash`, `python3`, `curl`, `zip`, `codesign`) are pre-installed on macOS

<details>
<summary><small>Quick installation (New theme, recommended)</small></summary><p>

#### Run the following command in Terminal:

```bash
bash <(curl -sSL 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.sh') --new-theme
```

#### or download and run [Install_Mac.sh](https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/Install_Mac.sh)

</p></details>

<details>
<summary><small>Full installation (all options, no prompts)</small></summary><p>

```bash
bash <(curl -sSL 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.sh') \
  --new-theme --podcasts-off --block-update --start-spotify --no-pause
```

</p></details>

<details>
<summary><small>Premium account installation (no ad-block)</small></summary><p>

```bash
bash <(curl -sSL 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.sh') \
  --premium --new-theme
```

</p></details>

<details>
<summary><small>Installing with parameters</small></summary><p>

| Flag | Description |
|------|-------------|
| `--premium` | No ad-blocking (for Premium users) |
| `--podcasts-off` | Hide podcasts / episodes / audiobooks from home |
| `--adsections-off` | Hide ad-like home sections |
| `--block-update` | Block Spotify auto-updates (prefs level) |
| `--no-shortcut` | Do not create a Desktop symlink |
| `--start-spotify` | Launch Spotify after patching |
| `--lyrics-block` | Disable native lyrics |
| `--devtools` | Enable Developer Tools in the client |
| `--new-theme` | Force new theme (new left/right sidebars) |
| `--mirror` | Use github.io mirror instead of raw.githubusercontent |
| `--no-pause` | Skip the "Press Enter to exit" prompt |
| `--spotify-path <path>` | Custom path to `Spotify.app` |
| `--custom-patches <path>` | Use a local `patches.json` file |
| `--lyrics-stat <color>` | Static lyrics colour (e.g. `spotify`, `blue`, `purple`) |

</p></details>

<h1 id="faq">FAQ</h1>

 Read [FAQ](https://telegra.ph/SpotX-FAQ-09-19)

<h1 id="disclaimer">Disclaimer</h1>

SpotX is a tool that modifies the official Spotify client, provided as an evaluation version — use it at your own risk.
