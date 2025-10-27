ARG ARCH=
FROM ${ARCH}ubuntu:24.04

RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi && \
    if getent group ubuntu >/dev/null 2>&1; then groupdel ubuntu; fi

RUN apt-get update && apt-get -y full-upgrade && \
    DEBIAN_FRONTEND=noninteractive apt-get -y install openssh-server mcrypt libcap2-bin \
      locales locales-all keyboard-configuration \
      rsyslog fail2ban iptables \
      rsync less vim nano diffutils git-core bash-completion zsh htop mariadb-client iputils-ping \
      && \
    mkdir /var/run/sshd && chmod 0755 /var/run/sshd && \
    git clone https://github.com/robbyrussell/oh-my-zsh.git /etc/skel/.oh-my-zsh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ADD rootfs/ /

RUN mkdir -p /etc/skel/.oh-my-zsh/custom/plugins && \
    rm -rf /etc/skel/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git /etc/skel/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    rm -rf /etc/skel/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/.git

RUN chmod +x /opt/docker/bin/* && /opt/docker/bin/bootstrap.sh

VOLUME ["/data"]
EXPOSE 22
WORKDIR /data
ENTRYPOINT ["/bin/bash"]
CMD ["/opt/docker/bin/entrypoint.sh"]
HEALTHCHECK --interval=1m0s --timeout=10s --start-period=10s --retries=3 CMD /opt/docker/bin/health.sh
