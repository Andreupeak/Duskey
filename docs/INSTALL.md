# Install Duskey

Download only from [Andreupeak/Duskey releases](https://github.com/Andreupeak/Duskey/releases).
This public beta is free, uses a local integrity signature, and is **not Apple-notarized**.
It does not include a Developer ID certificate or a publisher's personal certificate details.
macOS will normally show a first-open security warning for an Internet download.

1. Quit any older copy using its menu-bar **Quit** button, including the previous app named Lumina.
2. Open the downloaded `.dmg` and drag **Duskey.app** onto **Applications**.
   If you cannot write to Applications, put the app in your own `~/Applications` folder instead.
3. Eject the disk image. Open the installed app from Applications.
4. The app appears as a sun or moon in the menu bar. Click it to start setup.

The ZIP download is an alternative: unzip it, then move Duskey.app into Applications.

## Upgrading from the previous app name

Duskey has a new app name and bundle identifier. Quit the old app before opening Duskey
so two copies do not compete for keyboard control. On its first normal launch, Duskey
imports existing brightness settings, schedules, idle timeouts, and setup completion once.
Existing Duskey choices take precedence. Mac Location may need permission again.
After confirming your settings, move the previous app to Trash and replace any old Dock
shortcuts or manually configured login items with Duskey. The old preferences remain a
separate local backup; [PRIVACY.md](../PRIVACY.md) explains how to remove them.

## macOS first-open warning

Because this free release is not notarized, macOS may initially block it. If you have verified
that the download came from the official release and choose to trust it, Apple documents a
per-app exception under **System Settings → Privacy & Security → Open Anyway** after the first
launch attempt. Review the app name before confirming. Read
[Apple's explanation](https://support.apple.com/en-us/102445) before deciding.

Never disable Gatekeeper, SIP, or other system-wide security controls, and do not run commands
that remove quarantine attributes. A managed Mac may prohibit unnotarized apps; ask its administrator
or build from source. Source builds with free Xcode are documented in the repository README.

The download includes `SHA256SUMS.txt`. To verify integrity in Terminal, place it next to the
downloaded files and run `shasum -a 256 -c SHA256SUMS.txt`. A matching checksum detects changed
downloads; it is not independent verification of the publisher's identity or an Apple malware review.

## Setup and behavior

- **System:** choose a fixed brightness or ambient Auto-Brightness.
- **Periodic → Sun Cycle:** select Mac Location or save manual coordinates, then choose night brightness.
- **Periodic → Time Slots:** add up to three daily slots. Outside them, the backlight is off.
- **Inactivity Timeout:** click the minutes/seconds menus. A zero slot timeout uses the global setting.
- Manual coordinates work without location permission or a network connection. IP Estimate is optional
  and contacts an external provider only after confirmation.

No administrator password, Accessibility permission, or Input Monitoring permission is required
for normal operation. CoreBrightness support varies by Mac and macOS version; an unsupported
keyboard is reported instead of requesting broader permissions.

## Update, quit, and uninstall

Quit Duskey before replacing its app with a newer version. Your saved preferences remain local.
An identity-free update may require another macOS first-open or location permission decision.
Normal quit restores the keyboard state captured when Duskey launched. If the app crashes or is
force-quit, use macOS's keyboard-brightness controls to restore your preferred state.

To uninstall, quit Duskey and move the app to Trash. To forget location before uninstalling,
open Sun Cycle's location details and select **Forget Saved Location**. See the repository's
PRIVACY.md for removing all preferences. No helper service or background login item is installed.
