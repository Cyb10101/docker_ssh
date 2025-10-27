#!/usr/bin/env bash
set -e

pgrep -x rsyslogd > /dev/null 2>&1 || exit 1
pgrep -x sshd > /dev/null 2>&1 || exit 1
fail2ban-client ping > /dev/null 2>&1 || exit 1

exit 0
