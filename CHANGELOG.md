# Changelog

## 0.1.0-beta.1 — 2026-09-15

First public test package.

- Windows 11 x64 WPF dashboard for strict DoH status, on-demand game checks, optional public-exit check and temporary DNS-port observation.
- Manual persistent protection switch; no time-based switching.
- New-install path starts with protection disabled and only enrolls recognized SJTU adapters. Unknown/static adapters require an explicit in-app confirmation.
- DHCP and static-IP design records DNS only; it does not alter IP address, gateway, routes, proxy or VPN settings.

Known beta limits:

- The deep packet check uses Pktmon and intentionally refuses to run when another capture/filter may exist.
- Only a clean Windows 11 test matrix can promote this build beyond a developer preview.
- The package is unsigned. Download only from the project Release and verify SHA-256.
