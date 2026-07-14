# Captive Portal — Login no WiFi do Hotel

A maioria dos hotéis redireciona o tráfego HTTP para uma página de login antes de
liberar a internet. Como o Pi é quem faz o uplink, **o login é feito a partir do
Pi / da rede do Pi**, não do seu laptop conectado direto no hotel.

## Como isso funciona aqui (modo portal ↔ seguro)

O roteador tem dois modos, alternáveis em runtime pelo comando `travel-router`
(ou, no futuro, pelo web app em `http://192.168.88.1`):

| Modo | Roteamento dos clientes do AP | Quando usar |
|------|-------------------------------|-------------|
| `portal` | **direto** pela `wlan0` (sem Tailscale) | para abrir/completar o login do hotel |
| `secure` | **só** via Tailscale (exit node) | uso normal, depois de logar |

> ⚠️ No modo `portal` o tráfego passa em claro pela rede do hotel. Use só para o
> login e volte para `secure` em seguida.

## Não há "ovo e galinha"

O AP privado do Pi (`TravelRouter`, `192.168.88.1`) é uma **rede local** que sobe
primeiro e **independe de internet**. Você alcança o Pi por ela mesmo antes de
qualquer login no hotel.

## Fluxo ao chegar no hotel

1. Ligue o Pi. O AP privado sobe sozinho (sua `ap_password`, do `config.yml`).
2. Conecte seu laptop/celular no `TravelRouter`.
3. Entre em modo portal:
   ```bash
   ssh <user>@192.168.88.1 'sudo travel-router portal'
   ```
4. Abra qualquer site HTTP no navegador normal → o portal do hotel aparece → faça login.
5. Volte para o modo seguro:
   ```bash
   ssh <user>@192.168.88.1 'sudo travel-router secure'
   ```
6. Confirme:
   ```bash
   curl https://ifconfig.me   # deve mostrar o IP do exit node, não o do hotel
   ```

## Diagnóstico

```bash
ssh <user>@192.168.88.1 'sudo travel-router status'
# mostra: modo atual, uplink/canal, internet, tailscale, hostapd
```

## Alternativas de login (sem trocar de modo)

- **Navegador de texto no Pi:** `ssh <user>@192.168.88.1`, `sudo apt install -y w3m`,
  `w3m http://captive.apple.com`.
- **Proxy SOCKS:** `ssh -D 1080 <user>@192.168.88.1` e aponte o navegador para
  SOCKS5 `127.0.0.1:1080`.

## Dicas

- Alguns hotéis liberam por MAC. Dá para clonar o MAC do seu laptop na `wlan0`
  (ver histórico de MAC cloning) para pular o login em reconexões.
- Portais HTTPS podem exigir aceitar um certificado.
- Leases curtos (30 min) são renovados automaticamente pelo systemd-networkd.
