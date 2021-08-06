#!/usr/bin/env bash
set -e

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "${SCRIPTPATH}"

APPLICATION_UID=${APPLICATION_UID:-1000}
APPLICATION_GID=${APPLICATION_GID:-1000}
APPLICATION_USER=${APPLICATION_USER:-application}
APPLICATION_GROUP=${APPLICATION_GROUP:-application}

loadEnvironmentVariables() {
    if [ -f ".env" ]; then
      source .env
    fi
    if [ -f ".env.local" ]; then
      source .env.local
    fi
}

setDockerComposeFile() {
    DOCKER_COMPOSE_FILE=docker-compose.yml

    # Symfony
    APP_ENV=${APP_ENV:-}
    if [ "${APP_ENV}" == "dev" ]; then
        DOCKER_COMPOSE_FILE=docker-compose.dev.yml
    fi

    # TYPO3
    TYPO3_CONTEXT=${TYPO3_CONTEXT:-}
    if [ "${TYPO3_CONTEXT:0:11}" == "Development" ]; then
        DOCKER_COMPOSE_FILE=docker-compose.dev.yml
    fi

    # TYPO3
    WP_ENVIRONMENT_TYPE=${WP_ENVIRONMENT_TYPE:-}
    if [ "${WP_ENVIRONMENT_TYPE:0:11}" == "development" ]; then
        DOCKER_COMPOSE_FILE=docker-compose.dev.yml
    fi

    # Custom
    ENV_DOCKER_CONTEXT=${ENV_DOCKER_CONTEXT:-}
    if [ "${ENV_DOCKER_CONTEXT:0:11}" == "Development" ]; then
        DOCKER_COMPOSE_FILE=docker-compose.dev.yml
    fi
}

dockerComposeCmd() {
    docker-compose -f "${DOCKER_COMPOSE_FILE}" "${@:1}"
}

checkRoot() {
    if [[ $EUID -ne 0 ]]; then
        echo 'You must be a root user!' 2>&1
        exit 1
    fi
}

gitCheckBranch() {
    if [ -d ".git" ]; then
        if [[ $(git symbolic-ref --short -q HEAD) != "${1}" ]]; then
            echo "ERROR: Git is not on branch ${1}!"
            [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
        fi
    fi
}

gitCheckDirty() {
    if [ -d ".git" ]; then
        if [[ $(git diff --stat) != '' ]]; then
            echo
            git status --porcelain
            echo

            read -p 'Git is dirty... Continue? [y/N] ' -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
            fi
        fi
    fi
}

setPermissions() {
    chown -R ${APPLICATION_UID}:${APPLICATION_GID} .
    find . -type d -exec chmod ugo+rx,ug+w {} \;
    find . -type f -exec chmod ugo+r,ug+w {} \;
}

gitPullHost() {
    if [ -d ".git" ]; then
        git pull "${@:1}"
    fi
}

gitPullGuest() {
    if [ -d ".git" ]; then
        startFunction exec-web git pull "${@:1}"
    fi
}

composerInstall() {
    if [ -f "composer.json" ]; then
        startFunction exec-web composer install "${@:1}"
    fi
}

symfonyUpdateDatabase() {
    if [ -f "symfony.lock" ]; then
        read -p 'Update database schema? [y/N] ' -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            startFunction exec-web ./bin/console doctrine:schema:update --force
        fi
    fi
}

symfonyClearCache() {
    if [ -f "symfony.lock" ]; then
        startFunction exec-web ./bin/console cache:clear --no-warmup
        startFunction exec-web ./bin/console cache:warmup
    fi
}

deployImages() {
  # Default: 32 bit & 64 bit
  docker pull ubuntu:20.04
  docker build --no-cache --file Dockerfile --tag cyb10101/ssh:latest .
  docker push cyb10101/ssh:latest

  # Clean up
  docker rmi $(docker images --filter=reference="cyb10101/ssh:latest" -q)
  docker rmi $(docker images --filter=reference="ubuntu:20.04" -q)
}

runDeploy() {
    gitPullHost origin ${GIT_BRANCH}
    #setPermissions

    # Git: Deploy as user in container (SSH-Key for private repositories needed)
    #gitPullGuest origin ${GIT_BRANCH}

    # Deploy as user in container
    #startFunction start
    #composerInstall

    #symfonyUpdateDatabase
    #symfonyClearCache
}

loadEnvironmentVariables
GIT_BRANCH="${GIT_BRANCH:-master}"
setDockerComposeFile

startFunction() {
    case ${1} in
        start)
            startFunction pull && \
            startFunction build && \
            startFunction up
        ;;
        up)
            dockerComposeCmd up -d
        ;;
        down)
            dockerComposeCmd down --remove-orphans
        ;;
        login-root)
            dockerComposeCmd exec web bash
        ;;
        login)
            startFunction bash
        ;;
        bash)
            dockerComposeCmd exec -u ${APPLICATION_USER} web bash
        ;;
        zsh)
            dockerComposeCmd exec -u ${APPLICATION_USER} web zsh
        ;;
        exec-web)
            dockerComposeCmd exec -u ${APPLICATION_USER} web "${@:2}"
        ;;
        deploy-images)
          deployImages
        ;;
        deploy)
            checkRoot
            gitCheckBranch ${GIT_BRANCH}
            gitCheckDirty
            runDeploy
        ;;
        *)
            dockerComposeCmd "${@:1}"
        ;;
    esac
}

startFunction "${@:1}"
exit $?
