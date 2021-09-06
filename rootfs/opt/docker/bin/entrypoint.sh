#!/usr/bin/env bash
set -e

setDefaultVariables() {
  # Set default shell
  if [ "${SHELL}" != "false" ] && [ "${SHELL}" != "sh" ] && [ "${SHELL}" != "bash" ] && [ "${SHELL}" != "zsh" ]; then
    SHELL="bash"
  fi

  # Just generate a password if empty
  if [ "${PASSWORD}" == "" ]; then
    PASSWORD=`date +%s | sha256sum | base64 | head -c 32`
    #PASSWORD=`tr -dc '[:alnum:]' < /dev/urandom | head -c 32`
    echo "Password: ${PASSWORD}"
  fi
}

updateTimeZone() {
  if [ ! -z "${TZ}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone
  fi
}

updateLocale() {
  if [ ! -z "${LANG}" ]; then
    locale-gen ${LANG}
    update-locale LANG=${LANG}
    dpkg-reconfigure --frontend=noninteractive locales
    dpkg-reconfigure --frontend=noninteractive keyboard-configuration
  fi
}

createUserIfNotExists() {
  # User not exists
  if ! id "${APPLICATION_USER}" >/dev/null 2>&1; then
    echo "Create user ${APPLICATION_USER}..."
    # Add group
    groupadd -g "${APPLICATION_GID}" "${APPLICATION_GROUP}"

    # Add user without password
    #useradd -u "${APPLICATION_UID}" --home "${APPLICATION_HOME}" --create-home --shell /bin/${SHELL} --no-user-group "${APPLICATION_USER}" -k /etc/skel

    # Add user with password
    PASSWORD_ENCRYPTED=`openssl passwd -6 -salt $(tr -dc '[:alnum:]' < /dev/urandom | head -c 10) ${PASSWORD}`
    useradd -u "${APPLICATION_UID}" -p ${PASSWORD_ENCRYPTED} --home "${APPLICATION_HOME}" --create-home --shell /bin/${SHELL} --no-user-group "${APPLICATION_USER}" -k /etc/skel
    unset PASSWORD_ENCRYPTED

    # Assign user to group
    usermod -g "${APPLICATION_GROUP}" "${APPLICATION_USER}"
  fi
}

syncUserData() {
  # User exists
  if id -u "${APPLICATION_USER}" >/dev/null 2>&1; then
    # Sync skeleton only if shell enabled
    if [ "${ENABLE_SHELL}" == 1 ]; then
      rsync -av /etc/skel/ /data/
    fi

    # Add SSH directory, because /etc/skel doesn't copy that
    if [ ! -f "${APPLICATION_HOME}/.ssh/authorized_keys" ]; then
      mkdir -p ${APPLICATION_HOME}/.ssh
      touch ${APPLICATION_HOME}/.ssh/authorized_keys
      chown -R ${APPLICATION_USER}:${APPLICATION_GROUP} ${APPLICATION_HOME}/.ssh
    fi

    # Add SSH key if not exists
    if [ "${SSH_PUBLIC_KEY}" != "" ] && [ "`grep \"${SSH_PUBLIC_KEY}\" ${APPLICATION_HOME}/.ssh/authorized_keys`" == "" ]; then
      echo "${SSH_PUBLIC_KEY}" >> ${APPLICATION_HOME}/.ssh/authorized_keys
      chown ${APPLICATION_USER}:${APPLICATION_GROUP} ${APPLICATION_HOME}/.ssh/authorized_keys
    fi

    # Default permissions
    setUserPermissions "${APPLICATION_USER}" "${APPLICATION_GROUP}"

    # Set password
    echo "${APPLICATION_USER}":"${PASSWORD}" | chpasswd
  fi
}

setUserPermissions() {
  chmod 755 ${APPLICATION_HOME}
  chown ${1}:${2} ${APPLICATION_HOME}

  directories=(
    ".cache/"
    ".oh-my-zsh/"
  )

  files=(
    ".bash_logout"
    ".bashrc"
    ".profile"
    ".shell-methods.sh"
    ".zshrc"
  )

  for directory in ${directories[*]}; do
    if [ -d ${APPLICATION_HOME}/${directory} ]; then
      chown -R ${1}:${2} ${APPLICATION_HOME}/${directory}
    fi
  done

  for file in ${files[*]}; do
    if [ -f ${APPLICATION_HOME}/${file} ]; then
      chown ${1}:${2} ${APPLICATION_HOME}/${file}
    fi
  done
}

# Configure SSH daemon...
configureSshd() {
  # Only allow specified user
  if grep -E '^#?(AllowUsers) .*' /etc/ssh/sshd_config >/dev/null 2>&1; then
    sed -E -i "s/^#?(AllowUsers) .*/\1 ${APPLICATION_USER}/" /etc/ssh/sshd_config
  else
    echo "AllowUsers ${APPLICATION_USER}" >> /etc/ssh/sshd_config
  fi

  if ! [[ "${MAX_TRIES_SSH}" =~ ^[0-9]+$ ]]; then
    MAX_TRIES_SSH=6
  fi
  sed -E -i "s/^#?(MaxAuthTries) .*/\1 ${MAX_TRIES_SSH}/" /etc/ssh/sshd_config

  if [ "${SSH_KEYS_ONLY}" == 1 ]; then
    sed -E -i 's/^#?(PasswordAuthentication) .*/\1 no/' /etc/ssh/sshd_config
    #sed -E -i 's/^#?(ChallengeResponseAuthentication) .*/\1 no/' /etc/ssh/sshd_config
    #sed -E -i 's/^#?(UsePAM) .*/\1 no/' /etc/ssh/sshd_config
  fi

  if [ "${ENABLE_SHELL}" != 1 ]; then
    setUserPermissions "root" "${APPLICATION_GROUP}"

    sed -E -i 's/^#?(PermitTunnel) .*/\1 no/' /etc/ssh/sshd_config
    sed -E -i 's/^#?(Subsystem sftp) .*/\1 internal-sftp/' /etc/ssh/sshd_config
    sed -E -i 's/^#?(ChrootDirectory) .*/\1 %h/' /etc/ssh/sshd_config
    echo "ForceCommand internal-sftp" >> /etc/ssh/sshd_config
    echo "AllowTcpForwarding no" >> /etc/ssh/sshd_config

    # Jail sshfs user
#    if ! grep "Match User ${APPLICATION_USER}" /etc/ssh/sshd_config > /dev/null; then
#        echo "Match User ${APPLICATION_USER}" >> /etc/ssh/sshd_config
#        echo "      ChrootDirectory %h" >> /etc/ssh/sshd_config
#        echo "      X11Forwarding no" >> /etc/ssh/sshd_config
#        echo "      AllowTcpForwarding no" >> /etc/ssh/sshd_config
#        echo "      ForceCommand internal-sftp" >> /etc/ssh/sshd_config
#    fi
  fi
}

configureFail2Ban() {
  if [[ ! -z "${MAX_TRIES_BAN}" ]]; then
    sed -E -i "s/^#?(maxretry =).*/\1 ${MAX_TRIES_BAN}/" /etc/fail2ban/jail.d/sshd.conf
  fi

  if [[ ! -z "${FIND_TIME}" ]]; then
    sed -E -i "s/^#?(findtime =).*/\1 ${FIND_TIME}/" /etc/fail2ban/jail.d/sshd.conf
  fi

  if [[ ! -z "${BAN_TIME}" ]]; then
    sed -E -i "s/^#?(bantime =).*/\1 ${BAN_TIME}/" /etc/fail2ban/jail.d/sshd.conf
  fi
}

cleanup() {
  # Unset variables for security
  unset PASSWORD SSH_PUBLIC_KEY
}

APPLICATION_UID=${APPLICATION_UID:-1000}
APPLICATION_GID=${APPLICATION_GID:-1000}
APPLICATION_USER=${APPLICATION_USER:-application}
APPLICATION_GROUP=${APPLICATION_GROUP:-application}
APPLICATION_HOME="/data"
PASSWORD=${PASSWORD:-}
SSH_KEYS_ONLY=${SSH_KEYS_ONLY:-0}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-}
ENABLE_SHELL=${ENABLE_SHELL:-0}
SHELL=${SHELL:-bash}

setDefaultVariables
updateTimeZone
updateLocale

createUserIfNotExists
syncUserData

configureSshd
configureFail2Ban

cleanup

# Remove Socket file
if [ ! -z "$(service fail2ban status | grep 'is running')" ]; then
  service fail2ban stop
fi
if [ -S /var/run/fail2ban/fail2ban.sock ]; then
  rm /var/run/fail2ban/fail2ban.sock
fi

echo "Start services..."
service rsyslog restart
service ssh restart
service fail2ban restart

echo "Running..."
#tail -f /dev/null

# Stop container if health script fails, useful for "restart always"
while /opt/docker/bin/health.sh; do
  sleep 60
done
