# Docker SSH/SFTP Server

Docker file: [cyb10101/ssh](https://hub.docker.com/r/cyb10101/ssh)

If you only use `SFTP` you will get into a `chroot` environment.

Take a look in [docker-compose.yml](docker-compose.yml):

```yaml
version: "3.8"

services:
  ssh:
    image: cyb10101/ssh:latest
    restart: always
    # Optional: Set a nice hostname 
    hostname: example
    volumes:
      # Add paths (Example)
      - ../example_www:/data/example_www
      - ../example_forum:/data/example_forum
    ports:
      # Required: Set port to 2200 and listen on every ipv4 (Example)
      - "0.0.0.0:2200:22"
    environment:
      # Recommended: Set timezone and language
      - TZ=Europe/Berlin
      - LANG=de_DE.UTF-8

      # Optional: Set user login name 
      - APPLICATION_USER=application
      - APPLICATION_GROUP=application

      # Optional: If not set check autogenerated in logs
      - PASSWORD=Admin123!

      # Optional: Disable password login (Default: 0)
      - SSH_KEYS_ONLY=1

      # Optional: Add default public key
      - SSH_PUBLIC_KEY=ssh-rsa AB...iQ== user@example.org

      # Optional: Allow SSH access via terminal (Default only SFTP)
      - ENABLE_SHELL=1

      # Optional: bash, zsh, false
      - SHELL=zsh

      # Optional: Max tries per ssh login (Default: 6) [Multiple identity file fails (*.pub) + 3 Password fails = 4 fails]
      - MAX_TRIES_SSH=6

      # Optional: Number of failures before a host get banned (Default: 5) [Tries detected by logging]
      - MAX_TRIES_BAN=5

      # Optional: A host is banned if it has generated "maxretry" during the last "findtime" seconds (Default: 10m) [Days: 1d, Hours: 1h, Minutes: 1m]
      - FIND_TIME=1h

      # Optional: Ban time in seconds (Default: 10m) [Days: 1d, Hours: 1h, Minutes: 1m]
      - BAN_TIME=1h
    cap_add:
      - NET_ADMIN
      - NET_RAW
```

Connect via SSH:

```bash
ssh -p2200 application@example.org
```
