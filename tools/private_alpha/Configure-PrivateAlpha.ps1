[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $TailscaleIPv4,

    [string] $ClientDirectory = ""
)

$parsedAddress = $null
if (-not [System.Net.IPAddress]::TryParse($TailscaleIPv4, [ref] $parsedAddress) -or
    $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw "TailscaleIPv4 must be a valid IPv4 address."
}

$octets = $parsedAddress.GetAddressBytes()
if ($octets[0] -ne 100 -or $octets[1] -lt 64 -or $octets[1] -gt 127) {
    throw "Expected a Tailscale IPv4 address in 100.64.0.0/10, but received $TailscaleIPv4."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$serverConfigDirectory = Join-Path $repoRoot "data\local\private_alpha"
if ([string]::IsNullOrWhiteSpace($ClientDirectory)) {
    $ClientDirectory = Join-Path $repoRoot "exports\windows"
}

New-Item -ItemType Directory -Force -Path $serverConfigDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $ClientDirectory | Out-Null

$gatewayConfigPath = Join-Path $serverConfigDirectory "gateway_config.cfg"
$worldConfigPath = Join-Path $serverConfigDirectory "world_config.cfg"
$clientConfigPath = Join-Path $ClientDirectory "realmcraft_client.cfg"
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

$gatewayConfig = @"
[gateway-server]
port=8088
bind_address="$TailscaleIPv4"
certificate_path="res://data/config/tls/certificate.crt"
key_path="res://data/config/tls/key.key"

[gateway-manager-client]
port=8064
address="127.0.0.1"
certificate_path="res://data/config/tls/certificate.crt"
"@

$worldConfig = @"
[world-server]
port=8087
bind_address="$TailscaleIPv4"
certificate_path="res://data/config/tls/certificate.crt"
key_path="res://data/config/tls/key.key"
database_path="."
motd="WELCOME_REALMCRAFT_ALPHA"
name="RealmCraft Alpha"
max_players=25
hardcore=false
bonus_xp=0.0
max_character=5
pvp=false
public_url="$TailscaleIPv4"

[world-manager-client]
address="127.0.0.1"
port=8062
certificate_path="res://data/config/tls/certificate.crt"
"@

$clientConfig = @"
[network]
gateway_url="http://${TailscaleIPv4}:8088"
"@

[System.IO.File]::WriteAllText($gatewayConfigPath, $gatewayConfig, $utf8WithoutBom)
[System.IO.File]::WriteAllText($worldConfigPath, $worldConfig, $utf8WithoutBom)
[System.IO.File]::WriteAllText($clientConfigPath, $clientConfig, $utf8WithoutBom)

Write-Host "RealmCraft private-alpha configuration created for $TailscaleIPv4."
Write-Host "Gateway: $gatewayConfigPath"
Write-Host "World:   $worldConfigPath"
Write-Host "Client:  $clientConfigPath"
Write-Host "Only TCP 8087 and 8088 should be allowed across Tailscale. Keep 8062 and 8064 loopback-only."
