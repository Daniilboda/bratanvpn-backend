# BratanVPN AmneziaWG agent

Ограниченный скрипт для управления peers на VPN-сервере.

## Команды

```bash
sudo bratanvpn-awg-agent.sh status
sudo bratanvpn-awg-agent.sh add <public_key> <vpn_ip>
sudo bratanvpn-awg-agent.sh remove <public_key>
sudo bratanvpn-awg-agent.sh exists <public_key>
```

## Установка на VPS

```bash
sudo install -m 750 bratanvpn-awg-agent.sh /usr/local/sbin/bratanvpn-awg-agent
sudo bratanvpn-awg-agent status
```

По умолчанию:

- интерфейс: `awg0`
- конфиг: `/etc/amnezia/amneziawg/awg0.conf`

Переопределение:

```bash
export BRATANVPN_AWG_INTERFACE=awg0
export BRATANVPN_AWG_CONF=/etc/amnezia/amneziawg/awg0.conf
```

## Безопасность

- принимает только add/remove/exists/status
- валидирует формат public key и IP `10.8.0.x`
- не принимает произвольные shell-команды
- private key сервера не трогает и не печатает
