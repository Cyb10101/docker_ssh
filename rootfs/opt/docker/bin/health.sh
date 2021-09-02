#!/usr/bin/env bash
set -e

if [ -z "$(service rsyslog status | grep 'is running')" ]; then
  exit 1;
fi

if [ -z "$(service ssh status | grep 'is running')" ]; then
  exit 1;
fi

# fail2ban-client ping || exit 1
if [ -z "$(service fail2ban status | grep 'is running')" ]; then
  exit 1;
fi

exit 0
