# RPi5 Hotel Travel Router

Ansible + InSpec IaC to turn a **Raspberry Pi 5** into a travel router: connects to hotel WiFi, serves your own private AP, and routes all traffic through a **Tailscale exit node**.

```
[Hotel WiFi]
     ↑  wlan0 (client — uplink)
[Raspberry Pi 5]
     ↓  uap0 (AP — your private network)
[laptop]  [iPhone]  →  tailscale0  →  exit node (laptop2023)  →  internet
```

> **Both interfaces share the onboard radio.** AP and hotel uplink run on the same channel
> (limitation of single-radio concurrent mode). Performance is adequate for travel use.
> For better isolation, add a USB WiFi dongle (see [Upgrade: USB dongle](#upgrade-usb-dongle)).

---

## What it does

| Component | Role |
|-----------|------|
| `wlan0` | Client mode — connects to hotel WiFi (wpa_supplicant) |
| `uap0` | Virtual AP interface over `wlan0` (hostapd) |
| `dnsmasq` | DHCP + DNS for AP clients (192.168.88.0/24) |
| `nftables` | NAT/masquerade: AP clients → tailscale0 |
| `tailscale` | Connects to tailnet, sets exit node for all forwarded traffic |

---

## Quickstart

### 1. Prerequisites

- Raspberry Pi 5 running **Raspberry Pi OS Bookworm (64-bit)**
- SSH access with your key already in `~/.ssh/authorized_keys` on the Pi
- `ansible`, `ansible-vault` installed on your laptop
- `tailscale` running on the exit node (`laptop2023`) with exit node enabled:
  ```bash
  # On laptop2023:
  tailscale set --advertise-exit-node
  ```

### 2. Clone this repo

```bash
git clone https://github.com/rpagliuca/rpi5-hotel-travel-router
cd rpi5-hotel-travel-router/ansible
```

### 3. Set up secrets

```bash
cp inventory/group_vars/all/vault.yml.dist inventory/group_vars/all/vault.yml

# Edit vault.yml with your real credentials:
#   vault_ap_password     — your private AP password
#   vault_hotel_ssid      — hotel WiFi name (update per trip)
#   vault_hotel_password  — hotel WiFi password (update per trip)
#   vault_tailscale_authkey — from https://login.tailscale.com/admin/settings/keys

echo "my-vault-passphrase" > .vault_pass   # never commit this file
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

### 4. Update inventory

Edit `inventory/hosts.yml` and set `ansible_host` to your Pi's current IP.

### 5. Run the playbook

```bash
ansible-playbook playbook.yml
```

The Pi will:
1. Install hostapd, dnsmasq, nftables, wpa_supplicant, tailscale
2. Create the `uap0` virtual interface
3. Start the private AP (`RafTravel` by default)
4. Connect to hotel WiFi
5. Authenticate to Tailscale and set the exit node

### 6. Connect your devices

Join the `RafTravel` network (or your configured `ap_ssid`) with `vault_ap_password`.
All traffic exits via the Tailscale exit node.

Verify:
```bash
# From your laptop on the AP:
curl https://ifconfig.me   # should return exit node's IP, not hotel's IP
```

---

## Configuration

Edit `ansible/inventory/group_vars/all/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `ap_ssid` | `RafTravel` | Your private AP name |
| `ap_channel` | `6` | WiFi channel (must match hotel uplink channel) |
| `ap_ip` | `192.168.88.1` | Pi's IP on the AP subnet |
| `tailscale_exit_node` | `laptop2023` | Tailscale node to use as exit |
| `timezone` | `America/Sao_Paulo` | System timezone |

---

## Changing hotels (per-trip)

Only the hotel credentials change. Update `vault.yml` and re-run the `wifi-client` tag:

```bash
ansible-vault edit inventory/group_vars/all/vault.yml
# change vault_hotel_ssid and vault_hotel_password

ansible-playbook playbook.yml --tags wifi-client
```

---

## Captive portal (hotel login page)

See [docs/captive-portal.md](docs/captive-portal.md) for the full flow.

Short version: SSH into the Pi (`pi@192.168.88.1`) and complete the login with `w3m`, or use SSH port forwarding to open the portal in your laptop's browser.

---

## Running InSpec tests

```bash
# Install InSpec: https://docs.chef.io/inspec/install/
inspec exec inspec/ -t ssh://pi@<PI_IP> -i ~/.ssh/id_ed25519 --sudo
```

Controls:
- `ap_running.rb` — hostapd + uap0 interface + correct IP
- `tailscale_connected.rb` — tailscaled running + authenticated + exit node set
- `routing_enabled.rb` — IP forwarding + nftables masquerade rules
- `dns_dhcp.rb` — dnsmasq running + DHCP/DNS listening

---

## Upgrade: USB dongle

Using a USB dongle for uplink removes the same-channel constraint and improves throughput.

**Recommended chipset:** `mt7612u` (e.g. Comfast CF-912AC, ~£15).

Change vars:

```yaml
# main.yml
uplink_interface: "wlan1"   # USB dongle
ap_interface: "wlan0"       # onboard radio for AP (no virtual interface needed)
```

And remove the `uap0-create` service dependency from the `wifi-client` role — `wlan0` becomes the AP directly via hostapd.

---

## Architecture notes

- **No fallback NAT via hotel WiFi** — if Tailscale drops, AP clients lose internet intentionally (security: hotel WiFi is untrusted).
- **DNS pushed to clients:** Tailscale MagicDNS (`100.100.100.100`) + Cloudflare fallback (`1.1.1.1`).
- **AP clients can't reach hotel LAN** — `--exit-node-allow-lan-access` only allows the Pi itself (wlan0 subnet), not clients behind uap0.

---

## Security

- Never commit `vault.yml` or `.vault_pass` — both are in `.gitignore`
- Tailscale auth key: use a **pre-auth key with expiry** (`tag:travel-router`) from the admin console
- SSH password auth is disabled by the `base` role
