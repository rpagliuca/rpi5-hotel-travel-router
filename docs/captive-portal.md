# Captive Portal — Hotel Login Flow

Most hotels redirect HTTP traffic to a login page before granting internet access. Since the RPi handles the uplink, **you** need to complete the portal from the Pi itself (not from your laptop/iPhone, which are behind the Pi's AP).

## Method 1 — SSH into the Pi and use a text browser

```bash
# Connect to the Pi (it's already on your Tailscale network after first provisioning,
# or use its IP on your AP subnet: 192.168.88.1)
ssh pi@rpi5-travel-router

# Check if you have internet
curl -s --max-time 5 http://1.1.1.1 -o /dev/null && echo "online" || echo "captive portal"

# Open the portal in a text browser
sudo apt install -y w3m
w3m http://captive.apple.com     # triggers redirect to portal on most networks
# Navigate with arrow keys, fill form, press Enter
```

## Method 2 — SSH port forward + browser on laptop

Forward a local port to the Pi's `wlan0` interface so you can browse the portal from your laptop:

```bash
# On your laptop (connected to the Pi's AP or via Tailscale):
ssh -D 1080 pi@192.168.88.1

# Then configure your laptop's browser to use SOCKS5 proxy 127.0.0.1:1080
# Visit http://captive.apple.com — portal appears in your browser
# Complete login, then the Pi's wlan0 has internet
```

## Method 3 — MAC address cloning (pre-login)

Some hotels allow any device once you've logged in once with a specific MAC. Clone your laptop's MAC to the Pi's `wlan0`:

```bash
# On the Pi:
sudo ip link set wlan0 down
sudo ip link set wlan0 address AA:BB:CC:DD:EE:FF   # your laptop's MAC
sudo ip link set wlan0 up
sudo systemctl restart wpa_supplicant@wlan0
```

To make this permanent, set the MAC in the wpa_supplicant config:
```
network={
    ...
    mac_addr=1   # use current interface MAC
}
```

## After completing the portal

Once the Pi's `wlan0` has internet access, Tailscale will (re)connect and your AP clients will route through the exit node automatically. Verify:

```bash
tailscale status       # should show exit node active
curl https://ifconfig.me   # should show exit node's IP, not hotel IP
```

## Tips

- Keep a phone hotspot ready as backup (change `hotel_ssid`/`hotel_password` in vars and re-run the `wifi-client` role tag: `ansible-playbook playbook.yml --tags wifi-client`).
- Some hotels use HTTPS portals — you may need to accept a self-signed cert in the text browser.
- Hotel DHCP sometimes uses short leases (30 min). `dhcpcd` / `systemd-networkd` renews automatically.
