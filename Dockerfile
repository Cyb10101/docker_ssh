FROM ubuntu:20.04

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

RUN chmod +x /opt/docker/bin/* && /opt/docker/bin/bootstrap.sh

VOLUME ["/data"]
EXPOSE 22
WORKDIR /data
ENTRYPOINT ["/bin/bash"]
CMD ["/opt/docker/bin/entrypoint.sh"]
HEALTHCHECK --interval=1m0s --timeout=10s --start-period=10s --retries=3 CMD /opt/docker/bin/health.sh
