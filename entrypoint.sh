#!/usr/bin/env bash
set -e

APPLICATION_UID=${APPLICATION_UID:-1000}
APPLICATION_GID=${APPLICATION_GID:-1000}
APPLICATION_USER=${APPLICATION_USER:-application}
APPLICATION_GROUP=${APPLICATION_GROUP:-application}
APPLICATION_HOME="/data"
SFTP_ONLY=${SFTP_ONLY:-1}
PASSWORD=${PASSWORD:-}
SSH_KEYS_ONLY=${SSH_KEYS_ONLY:-0}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-}
SHELL=${SHELL:-bash}

# Set default shell
if [ "${SHELL}" != "false" ] && [ "${SHELL}" != "sh" ] && [ "${SHELL}" != "bash" ] && [ "${SHELL}" != "zsh" ]; then
  SHELL="bash"
fi

# Just generate a password if empty
if [ "${PASSWORD}" == "" ]; then
  PASSWORD=`date +%s | sha256sum | base64 | head -c 32`
  echo "Password: ${PASSWORD}"
fi

# User not exists
if ! id "${APPLICATION_USER}" >/dev/null 2>&1; then
  echo "Create user ${APPLICATION_USER}..."
  # Add group
  groupadd -g "${APPLICATION_GID}" "${APPLICATION_GROUP}"

  # Add user
  useradd -u "${APPLICATION_UID}" --home "${APPLICATION_HOME}" --create-home --shell /bin/${SHELL} --no-user-group "${APPLICATION_USER}" -k /etc/skel

  # Assign user to group
  usermod -g "${APPLICATION_GROUP}" "${APPLICATION_USER}"
fi

# User exists
if id -u "${APPLICATION_USER}" >/dev/null 2>&1; then
  # Add SSH key, because /etc/skel doesn't copy that
  if [ ! -f "${APPLICATION_HOME}/.ssh/authorized_keys" ] && [ "${SSH_PUBLIC_KEY}" != "" ]; then
    mkdir -p ${APPLICATION_HOME}/.ssh
    echo "${SSH_PUBLIC_KEY}" >> ${APPLICATION_HOME}/.ssh/authorized_keys
    chown -R ${APPLICATION_USER}:"${APPLICATION_GROUP}" ${APPLICATION_HOME}/.ssh
  fi

  # Default permissions
  chown ${APPLICATION_GROUP}:"${APPLICATION_GROUP}" ${APPLICATION_HOME}

  # Set password
  echo "${APPLICATION_USER}":"${PASSWORD}" | chpasswd
fi

echo "Configure SSH daemon..."
sed -E -i 's/^#?(PermitRootLogin) .*/\1 no/' /etc/ssh/sshd_config
sed -E -i 's/^#?(RSAAuthentication) .*/\1 no/' /etc/ssh/sshd_config
sed -E -i 's/^#?(PasswordAuthentication) .*/\1 yes/' /etc/ssh/sshd_config
sed -E -i 's/^#?(X11Forwarding) .*/\1 no/' /etc/ssh/sshd_config
sed -E -i 's/^#?(PrintLastLog) .*/\1 no/' /etc/ssh/sshd_config

if [ "${SSH_KEYS_ONLY}" == 1 ]; then
  sed -E -i 's/^#?(PasswordAuthentication) .*/\1 no/' /etc/ssh/sshd_config
fi

if [ "${SFTP_ONLY}" == 1 ]; then
  chown root:"${APPLICATION_GROUP}" ${APPLICATION_HOME}

  sed -E -i 's/^#?(Subsystem sftp) .*/\1 internal-sftp/' /etc/ssh/sshd_config
  echo "ChrootDirectory %h" >> /etc/ssh/sshd_config
  echo "ForceCommand internal-sftp" >> /etc/ssh/sshd_config
  echo "AllowTcpForwarding no" >> /etc/ssh/sshd_config
fi

echo "Running SSH daemon..."
# Pass all remaining arguents to sshd. This enables to override some options through -o.
exec /usr/sbin/sshd -D -e "$@"
