# nasmon

Checks a NAS's RAID arrays, disk temperatures and volume usage over ssh, and publishes the result to
MQTT as one JSON message (retained), for [mqtt-watchdog](https://github.com/matthewgream/mqtt-watchdog)
to turn into email and ntfy alerts. Runs every 4 hours from a systemd timer. Nothing is installed on
the NAS: each run sends one shell command (`cat /proc/mdstat`, `df -k`, QNAP's `get_hd_temp`,
`cat /proc/uptime`) and parses what comes back.

| | |
|---|---|
| `nasmon` | the tool (Node, no npm deps; uses `ssh`, `sshpass`, `mosquitto_pub`) |
| `nasmon.timer` | runs `nasmon.service` every 4 hours (at 00:15, 04:15, ...) and 10 min after boot |

Written for an old QNAP (TS-409 Pro, firmware 3.3, three of four bays filled):

- its root filesystem is a ramdisk, so an ssh key added for `admin` is gone after a reboot: the
  password is used instead, through `sshpass -e` (so it never shows in the process list). Leave
  `password` empty to log in with root's ssh key on a NAS that keeps one.
- its OpenSSH 4.6 only offers `ssh-rsa` host keys, which current clients refuse unless asked.
- its system arrays (`md9`, `md13`) are built for every bay, so with a bay empty they always look
  degraded (`[UUU_]`): `array-md9=3` sets the count they are judged against.

## Install

```sh
apt install sshpass mosquitto-clients
make test         # check the NAS and print the message, without publishing
make install      # tool, config, timer
make run          # a check now
make status       # timer, last run, last log lines
```

Config goes to `/etc/default/nasmon` (mode 600: it holds the NAS password). A per-host
`nasmon.<hostname>.cfg` is used instead of `nasmon.cfg` when present. The NAS's host key is
recorded on first contact in `/var/lib/nasmon/known_hosts`.

## Message

Published to `system/storage/<name>`:

```json
{
  "name": "workdisk", "host": "workdisk.local", "time": "2026-10-21 10:28:12",
  "ok": true, "healthy": true, "problems": [], "uptime": 339424,
  "arrays": [
    { "id": "workdisk/md0", "name": "md0", "level": "raid1", "state": "active", "status": "[UUU]",
      "devices": 3, "active": 3, "expected": 3, "failed": 0, "spare": 0, "members": "sda3 sdc3 sdb3",
      "healthy": true, "mount": "/share/MD0_DATA", "size_gb": 1967.9, "free_gb": 1624.6, "used": 17, "full": false }
  ],
  "disks": [ { "id": "workdisk/hd1", "name": "hd1", "bay": 1, "temp": 31, "hot": false } ]
}
```

- an array is `healthy` when it is not inactive, has no failed member, and has at least `expected`
  active members (`array-<md>`, else its own member count). `spares`, `faulty` and `sync` (resync,
  recovery, check progress) appear when there are any.
- a disk is `hot` at `temp-hot` (default 50 °C); a volume `full` at `usage-full` (default 90 %).
- `problems` lists everything wrong, in words, and `healthy` is true when there is nothing.
- when the NAS cannot be checked at all, the message is `{ "ok": false, "error": "..." }` instead.

## Alerts

With mqtt-watchdog, e.g.:

```ini
# two missed runs warn, a third has the watchdog run the check again
topic.5.name=system/storage/workdisk
topic.5.service=nasmon.service
topic.5.warning=30600
topic.5.restart=45000
topic.5.recover=true

alert.7.name=RAID degraded
alert.7.topic=system/storage/+
alert.7.array=arrays
alert.7.key=id
alert.7.field=healthy
alert.7.equals=false
alert.7.details=status,active,expected,faulty,spares,sync,members
alert.7.repeat=1d
alert.7.priority=high

alert.8.name=Disk hot
alert.8.topic=system/storage/+
alert.8.array=disks
alert.8.key=id
alert.8.field=hot
alert.8.equals=true
alert.8.details=temp

alert.9.name=Volume full
alert.9.topic=system/storage/+
alert.9.array=arrays
alert.9.key=id
alert.9.field=full
alert.9.equals=true
alert.9.details=used,free_gb,mount

# one failed check is left for the next run to clear
alert.10.name=NAS check failed
alert.10.topic=system/storage/+
alert.10.field=ok
alert.10.equals=false
alert.10.hold=5h
alert.10.details=error
```

## License

CC BY-NC-SA 4.0 — see [LICENSE](LICENSE).
