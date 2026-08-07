# RealmCraft private alpha

This setup exposes only the player-facing gateway and world sockets through a
Tailscale machine share. It is intended for a small, controlled commercial
alpha—not as the final public hosting architecture.

## Network boundary

| Port | Role | Exposure |
| --- | --- | --- |
| TCP 8088 | Gateway HTTP API | Tailscale testers only |
| TCP 8087 | World WebSocket | Tailscale testers only |
| TCP 8064 | Master-to-gateway control | Loopback only |
| TCP 8062 | Master-to-world control | Loopback only |

Never expose the database, admin dashboard, 8062, or 8064 to the VPN or public
Internet.

## Generate the configuration

After Tailscale is installed on the host, get its IPv4 address:

```powershell
tailscale ip -4
```

Then run:

```powershell
.\tools\private_alpha\Configure-PrivateAlpha.ps1 -TailscaleIPv4 100.x.y.z
```

This creates ignored, machine-local server configuration under
`data/local/private_alpha` and places `realmcraft_client.cfg` beside the exported
Windows client. The address can change without rebuilding the EXE.

Run the gateway with:

```text
--config=res://data/local/private_alpha/gateway_config.cfg
```

Run the world server with:

```text
--config=res://data/local/private_alpha/world_config.cfg
```

The master server continues using `data/config/master_config.cfg`, whose control
listeners remain bound to `127.0.0.1`.

## Windows Firewall

From an elevated PowerShell window on the host, allow only Tailscale's IPv4
range to the two player-facing TCP ports:

```powershell
New-NetFirewallRule -DisplayName "RealmCraft Alpha Gateway (Tailscale)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8088 -RemoteAddress 100.64.0.0/10 -Profile Any
New-NetFirewallRule -DisplayName "RealmCraft Alpha World (Tailscale)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8087 -RemoteAddress 100.64.0.0/10 -Profile Any
```

Do not add inbound rules for ports 8062 or 8064.

## Distribution

Each tester receives the complete client folder, including
`RealmCraft-Alpha.exe` and `realmcraft_client.cfg`. Because the alpha binary is
not yet code-signed, Windows may identify it as an unknown publisher. Provide a
SHA-256 checksum with every build; do not instruct testers to disable Defender
or SmartScreen globally.
