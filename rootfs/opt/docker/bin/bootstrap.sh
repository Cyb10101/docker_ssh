#!/usr/bin/env bash
set -e

configureSkeleton() {
  echo "source ~/.shell-methods.sh" >> /etc/skel/.bashrc
  echo "bashCompletion" >> /etc/skel/.bashrc
  echo "addAlias" >> /etc/skel/.bashrc
  echo "stylePS1" >> /etc/skel/.bashrc
}

syncRoot() {
  rsync -a /etc/skel/ /root/
}

# Motd - Message of the day
configureMotd() {
    files=(
      "10-help-text"
      "50-motd-news"
      "60-unminimize"
    )

    for file in ${files[*]}; do
      if [ -f /etc/update-motd.d/${file} ]; then
        rm /etc/update-motd.d/${file}
      fi
    done

    echo '' > /etc/legal
}

# Configure rsyslog daemon...
configureRsyslog() {
  sed -E -i 's/^#?(module\(load="imklog" .*)/# \1/' /etc/rsyslog.conf
}

# Configure SSH daemon
configureSshd() {
  sed -E -i 's/^#?(PermitRootLogin) .*/\1 no/' /etc/ssh/sshd_config
  sed -E -i 's/^#?(RSAAuthentication) .*/\1 no/' /etc/ssh/sshd_config
  sed -E -i 's/^#?(PasswordAuthentication) .*/\1 yes/' /etc/ssh/sshd_config
  sed -E -i 's/^#?(X11Forwarding) .*/\1 no/' /etc/ssh/sshd_config
  sed -E -i 's/^#?(PrintLastLog) .*/\1 no/' /etc/ssh/sshd_config
}

configureSkeleton
syncRoot
configureMotd
configureRsyslog
configureSshd
