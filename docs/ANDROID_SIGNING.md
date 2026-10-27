# Android signing and one-click installs

All Hub is a launcher, not a place to store private signing keys. Keep every `.jks` file and password outside Git.

## Required GitHub Actions secrets

Set these in each repository's **Settings → Secrets and variables → Actions**.

| App | Repository | Secrets |
| --- | --- | --- |
| All Hub | PerchikHot/all-hub | `ALLHUB_KEYSTORE_BASE64`, `ALLHUB_STORE_PASSWORD`, `ALLHUB_KEY_PASSWORD`, `ALLHUB_KEY_ALIAS` |
| Kopilka | PerchikHot/all-hub | `KOPILKA_KEYSTORE_BASE64`, `KOPILKA_STORE_PASSWORD`, `KOPILKA_KEY_PASSWORD`, `KOPILKA_KEY_ALIAS` |
| Shadow RP | PerchikHot/Shadow-rp | `SHADOWRP_KEYSTORE_BASE64`, `SHADOWRP_KEYSTORE_PASSWORD`, `SHADOWRP_KEY_PASSWORD`, `SHADOWRP_KEY_ALIAS` |

The `*_KEYSTORE_BASE64` secret is the single-line base64 encoding of the binary keystore, **not its path**. On Windows PowerShell:
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\\path\\to\\app-release.jks")) | Set-Clipboard
```
Paste the copied value into the corresponding GitHub secret. Use the alias and passwords from your private records.

**Eclipse Arena:** its existing workflow currently uses a persistent *debug* keystore. Switching it to a release keystore requires changing the Godot export configuration and workflow, and the new APK cannot update a build signed with the previous debug certificate.

## Update safety

- Never regenerate or rotate a signing key for an already installed Android package without a deliberate migration plan.
- Keep package names stable and increment version codes for upgrades.
- A GitHub Actions artifact is not a direct APK download. Publish signed APKs as GitHub Release assets for one-click installation.
- Android always requires user confirmation to install or update an APK.
- All Hub's release downloader only accepts direct HTTPS `.apk` links from github.com.
- Never commit `.jks`, `.keystore`, password files or base64 key material.
