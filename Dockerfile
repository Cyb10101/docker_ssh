FROM ubuntu:20.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server mcrypt \
      rsync less vim nano diffutils git-core bash-completion zsh htop mariadb-client iputils-ping \
      && \
    mkdir /var/run/sshd && chmod 0755 /var/run/sshd && \
    git clone https://github.com/robbyrussell/oh-my-zsh.git /etc/skel/.oh-my-zsh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY .shell-methods.sh .zshrc /etc/skel/
COPY .oh-my-zsh/custom/plugins/ssh-agent/ssh-agent.plugin.zsh /etc/skel/.oh-my-zsh/custom/plugins/ssh-agent/
COPY .oh-my-zsh/custom/themes/cyb.zsh-theme /etc/skel/.oh-my-zsh/custom/themes/

RUN echo "source ~/.shell-methods.sh" >> /etc/skel/.bashrc && \
  echo "bashCompletion" >> /etc/skel/.bashrc && \
  echo "addAlias" >> /etc/skel/.bashrc && \
  echo "stylePS1" >> /etc/skel/.bashrc && \
  rsync -av /etc/skel/ /root/ && \
  rm /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news

COPY entrypoint.sh /root/
COPY motd /etc/update-motd.d/00-header

VOLUME ["/data"]
EXPOSE 22
WORKDIR /data
ENTRYPOINT ["/bin/bash"]
CMD ["/root/entrypoint.sh"]
