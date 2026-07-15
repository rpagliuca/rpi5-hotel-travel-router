# RPi5 Hotel Travel Router

Ansible + InSpec IaC to turn a **Raspberry Pi 5** into a travel router: connects to hotel WiFi, serves your own private AP, and routes all traffic through a **Tailscale exit node**.

```
[Hotel WiFi]
     ↑  wlan0 (client — uplink)
[Raspberry Pi 5]
     ↓  uap0 (AP — your private network)
[laptop]  [phone]  →  tailscale0  →  exit node (your tailnet)  →  internet
```

> **Both interfaces share the onboard radio.** AP and hotel uplink run on the same channel
> (limitation of single-radio concurrent mode). Performance is adequate for travel use.
> For better isolation, add a USB WiFi dongle (see [Upgrade: USB dongle](#upgrade-usb-dongle)).

---

## Fundação: o AP privado nunca cai 🛡️

A prioridade nº1 é **nunca perder acesso ao Pi**. O AP privado (`TravelRouter`,
`192.168.88.1`) é a âncora de segurança:

- **Sobe primeiro e desacoplado.** `hostapd` depende apenas do `uap0-create`
  (interface local) — **não** espera hotel, Tailscale ou roteamento. Se qualquer
  etapa seguinte falhar, o AP continua de pé e você entra por `ssh <user>@192.168.88.1`.
- **Auto-recupera.** `hostapd` roda com `Restart=always`, e um **watchdog**
  (`ap-watchdog`, a cada 60s) repara `uap0`, o IP estático, o `hostapd` e o
  `dnsmasq` se algo cair.
- **Senha pessoal.** O AP usa WPA2 com a sua `ap_password` (do `config.yml`) —
  só você entra. SSH pela sub-rede do AP é sempre liberado no firewall.
- **Rádio único:** o canal do AP é re-sincronizado (best-effort) com o canal do
  hotel *depois* de o AP já estar no ar — sem nunca bloquear a subida do AP.

## Modos: `portal` ↔ `secure`

Redes de hotel exigem login (captive portal) e são não-confiáveis. Por isso há
dois modos, alternáveis em runtime:

```bash
sudo travel-router portal   # clientes saem DIRETO pela wlan0 (para logar no hotel)
sudo travel-router secure   # clientes saem SÓ via Tailscale (uso normal)
sudo travel-router status   # modo, uplink, internet, tailscale, hostapd
```

Boot inicia no modo `travel_router_boot_mode` (padrão `secure`). Detalhes do login:
[docs/captive-portal.md](docs/captive-portal.md).

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

- Raspberry Pi 5 running **Raspberry Pi OS Bookworm ou Trixie (64-bit)**
- SSH access with your key already in `~/.ssh/authorized_keys` on the Pi
- `ansible` installed on your laptop (`pipx install ansible` ou `brew install ansible`)
- A **Tailscale exit node** já rodando na sua tailnet, com o exit node habilitado:
  ```bash
  # No dispositivo que será o exit node:
  tailscale set --advertise-exit-node
  ```
  (aprove-o em https://login.tailscale.com/admin/machines)

### 2. Clone this repo

```bash
git clone https://github.com/rpagliuca/rpi5-hotel-travel-router
cd rpi5-hotel-travel-router/ansible
```

### 3. Crie seu config.yml (gitignored)

Todos os valores específicos do seu ambiente (IP do Pi, SSIDs, senhas, authkey,
exit node) ficam em `config.yml` — que **nunca** é comitado. Não há vault: como o
arquivo é gitignored, os segredos jamais vão para o repositório.

```bash
cp config.example.yml config.yml
$EDITOR config.yml   # preencha TODOS os campos (veja os comentários no arquivo)
```

Campos obrigatórios: `ansible_host`, `ansible_user`, `ap_ssid`, `ap_password`,
`hotel_ssid`, `hotel_open`/`hotel_password`, `tailscale_authkey`, `tailscale_exit_node`.

### 4. Run the playbook

```bash
ansible-playbook playbook.yml -e @config.yml
```

O playbook valida o `config.yml` no início (falha rápido se faltar algo) e então:
1. Sobe **primeiro** o AP privado (`ap_ssid`, sua senha) — a âncora que não cai
2. Instala hostapd, dnsmasq, nftables, wpa_supplicant, tailscale
3. Conecta no Wi-Fi do hotel (uplink)
4. Autentica no Tailscale
5. Aplica o modo padrão (`secure`): clientes → Tailscale → exit node

### 5. Connect your devices

Conecte no seu AP (`ap_ssid`) com a senha `ap_password`. No modo `secure`, todo o
tráfego sai pelo exit node do Tailscale.

Verify:
```bash
# Do seu laptop conectado no AP:
curl https://ifconfig.me   # deve mostrar o IP do exit node, não o do hotel
```

---

## Web de configuração (sem SSH) 🌐

Conectado no AP privado, abra **`http://192.168.88.1`** (`ap_ip`) no navegador do
laptop ou celular. É um app single-page servido pelo próprio Pi (Flask, role
`webapp`, só escuta na interface do AP) para operar o roteador **sem terminal**:

- **Status** — uplink conectado, IP, internet, estado do Tailscale + exit node e
  quantos dispositivos estão no seu AP (auto-refresh a cada 5 s).
- **Escolher o Wi-Fi do hotel** — escaneia as redes ao redor, você seleciona o
  SSID, marca se é aberta ou digita a senha, e aplica — sem editar `config.yml`.
- **Alternar modo** `secure` ↔ `portal` num toque (ver seção de modos abaixo).
- **Manutenção** — reiniciar o Pi ou disparar o rollback manual.

O AP e essa página sobem **independentes** do hotel/Tailscale: mesmo se o uplink
falhar, você continua com acesso à configuração. A porta é `webapp_port` (padrão
`80`) em `main.yml`.

---

## Configuration

**Valores do seu ambiente** (SSIDs, senhas, authkey, exit node, IP do Pi): em
`config.yml` (a partir de `config.example.yml`). Veja os campos lá.

**Defaults genéricos** (raramente mudam): `ansible/inventory/group_vars/all/main.yml`.
Para sobrescrever um deles, basta colocar a chave no seu `config.yml` (extra-vars
via `-e @config.yml` têm precedência sobre o `main.yml`).

| Variável (config.yml) | Exemplo | Descrição |
|-----------------------|---------|-------------|
| `ap_ssid` / `ap_password` | `TravelRouter` / *forte* | Seu AP privado e a senha (só você sabe) |
| `hotel_ssid` | `GTvisitor` | Wi-Fi do hotel (muda por viagem) |
| `hotel_open` / `hotel_password` | `true` / `""` | Rede aberta (ex.: GTvisitor) ou com senha |
| `tailscale_authkey` | `tskey-auth-…` | Auth key da sua tailnet |
| `tailscale_exit_node` | *nome exato* | Nó usado como exit (nome de `tailscale status` ou IP) |
| `travel_router_boot_mode` | `secure` | Modo no boot (`secure`/`portal`) — opcional |
| `timezone` | `America/Sao_Paulo` | Fuso — opcional |

> **OS:** Raspberry Pi OS **Bookworm ou Trixie** (64-bit).

---

## Aplicar remotamente com segurança (deadman rollback) 🪂

Aplicar esta config **via SSH remoto** é arriscado: os roles mexem na `wlan0` e
sobem o AP no mesmo rádio — se algo falhar, você pode **perder o acesso** ao Pi.
Para isso existe o **deadman switch** (role `rollback-guard`), opt-in:

```bash
ansible-playbook playbook.yml -e @config.yml -e deadman_rollback=true
```

Ao final, o Pi fica **armado**: se o heartbeat não for tocado dentro de
`deadman_timeout_sec` (padrão 300s), ele **reverte ao estado base** (`wlan0` de
volta ao NetworkManager, Tailscale sem exit node, sem AP/NAT) e reinicia.

Fluxo:

```bash
# Enquanto valida, mantenha vivo a cada < 5 min (de outra máquina, via SSH):
watch -n 60 ssh <user>@<pi> sudo travel-router-keepalive

# Deu tudo certo e você continua com acesso? Torne permanente:
ssh <user>@<pi> sudo travel-router-commit

# Reverter manualmente a qualquer momento:
ssh <user>@<pi> sudo travel-router-rollback
```

Se você **perder o acesso**, é só esperar ≤5 min: o Pi volta sozinho ao estado
anterior. Os CLIs `travel-router-{keepalive,commit,rollback}` ficam sempre
instalados; o deadman só fica *armado* quando `deadman_rollback=true`.

---

## Changing hotels (per-trip)

Só as credenciais do hotel mudam. Edite `config.yml` (`hotel_ssid`,
`hotel_open`/`hotel_password`) e rode só a tag `wifi-client`:

```bash
$EDITOR config.yml
ansible-playbook playbook.yml -e @config.yml --tags wifi-client
```

Ou, sem ansible, direto no Pi via o web app do AP (roadmap) / `travel-router`.

---

## Captive portal (hotel login page)

See [docs/captive-portal.md](docs/captive-portal.md) for the full flow.

Versão curta: conecte no AP `TravelRouter`, entre em modo portal
(`ssh <user>@192.168.88.1 'sudo travel-router portal'`), faça o login do hotel no
navegador normal e volte para `sudo travel-router secure`.

---

## Running InSpec tests

```bash
# Install InSpec: https://docs.chef.io/inspec/install/
# Use o ansible_user e ansible_host do seu config.yml:
inspec exec inspec/ -t ssh://<ansible_user>@<ansible_host> -i ~/.ssh/id_ed25519 --sudo
```

Controls:
- `ap_running.rb` — hostapd + uap0 interface + correct IP
- `uplink.rb` — wpa_supplicant uplink running + NM unmanaged + internet reachable
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

- **NetworkManager (Bookworm/Trixie default) is told to ignore `wlan0`/`uap0`** — those are managed by wpa_supplicant + systemd-networkd + hostapd. `eth0` stays under NetworkManager, so plugging an ethernet cable into a hotel port gives an uplink automatically (Tailscale rides over whichever uplink is active).
- **No fallback NAT via hotel WiFi** — if Tailscale drops, AP clients lose internet intentionally (security: hotel WiFi is untrusted).
- **DNS pushed to clients:** Tailscale MagicDNS (`100.100.100.100`) + Cloudflare fallback (`1.1.1.1`).
- **AP clients can't reach hotel LAN** — `--exit-node-allow-lan-access` only allows the Pi itself (wlan0 subnet), not clients behind uap0.

---

## Security

- **Nunca comite `config.yml`** — ele tem seus segredos e está no `.gitignore`.
  Este repo é público e reutilizável: todo dado pessoal fica no seu `config.yml` local.
- Tailscale auth key: use uma **pre-auth key com expiração** (idealmente `tag:…`) do admin console.
- SSH password auth is disabled by the `base` role.
- O AP privado usa WPA2 com a sua `ap_password` — só você entra na rede de gestão.
