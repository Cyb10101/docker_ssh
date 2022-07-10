#!/usr/bin/env bash
set -e; # Exit on error

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

isContextDevelopment() {
    # Symfony
    APP_ENV=${APP_ENV:-}
    if [ "${APP_ENV}" == "dev" ]; then
        echo 1;
        return;
    fi

    # TYPO3
    TYPO3_CONTEXT=${TYPO3_CONTEXT:-}
    if [ "${TYPO3_CONTEXT:0:11}" == "Development" ]; then
        echo 1; return;
    fi

    # TYPO3
    WP_ENVIRONMENT_TYPE=${WP_ENVIRONMENT_TYPE:-}
    if [ "${WP_ENVIRONMENT_TYPE:0:11}" == "development" ]; then
        echo 1; return;
    fi

    # Custom
    ENV_DOCKER_CONTEXT=${ENV_DOCKER_CONTEXT:-}
    if [ "${ENV_DOCKER_CONTEXT:0:11}" == "Development" ]; then
        echo 1; return;
    fi

    echo 0;
}

setDockerComposeFile() {
    DOCKER_COMPOSE_FILE=docker-compose.yml
    if [ "$(isContextDevelopment)" == "1" ]; then
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

findBinaryByWhich() {
  set +e
  binary=$(which "${1}")
  if [ $? -ne 0 ]; then
    return
  fi
  set -e
  echo ${binary}
  return
}

setPermissions() {
    chown -R ${APPLICATION_UID}:${APPLICATION_GID} .
    find . -type d -exec chmod ugo+rx,ug+w {} \;
    find . -type f -exec chmod ugo+r,ug+w {} \;
}

gitPull() {
    if [ -d ".git" ]; then
        git pull "${@:1}"
    fi
}

composerInstall() {
    if [ -f "composer.json" ]; then
        ${BIN_PHP} ${BIN_COMPOSER} --no-interaction install "${@:1}"
    fi
}

symfonyUpdateDatabase() {
    if [ -f "symfony.lock" ] && [ ! -z "${DATABASE_URL}" ]; then
        read -p 'Update database schema? [y/N] ' -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ${BIN_PHP} ./bin/console doctrine:schema:update --force
        fi
    fi
}

symfonyClearCache() {
    if [ -f "symfony.lock" ]; then
        ${BIN_PHP} ./bin/console cache:clear --no-warmup
        ${BIN_PHP} ./bin/console cache:warmup
    fi
}

deployImages() {
  # Default: 32 bit & 64 bit
  docker pull ubuntu:20.04
  docker build --no-cache --file Dockerfile --tag cyb10101/ssh:latest .
  docker push cyb10101/ssh:latest

  # Clean up
  set +e
  docker rmi $(docker images --filter=reference="cyb10101/ssh:latest" -q)
  docker rmi $(docker images --filter=reference="ubuntu:20.04" -q)
  set -e
}

runDeploy() {
    checkRoot
    gitCheckBranch ${GIT_BRANCH}
    gitCheckDirty

    # Task 1: Deploy Git as root in server
    gitPull origin ${GIT_BRANCH}
    setPermissions

    # Task 2: Deploy as user in container (Docker)
    startFunction start
    startFunction exec-web ./start.sh deployDirect

    # Task 2: Deploy as user in system (Switch from root to user)
    #if [ -z "${RUN_AS_USERNAME}" ]; then echo 'Error variable RUN_AS_USERNAME is empty!'; exit 1; fi
    #runuser -u ${RUN_AS_USERNAME} -- ./start.sh deployDirect

    # Task 2: Deploy directly (Webhosting)
    #startFunction deployDirect
}

# Deploy directly (In Docker container or Webhosting)
deployDirect() {
    # For in Container or Webhosting (SSH-Key for private repositories needed)
    #gitPull origin ${GIT_BRANCH}

    composerInstall
    symfonyUpdateDatabase
    symfonyClearCache
}

loadEnvironmentVariables
if [ -z "${BIN_PHP}" ]; then BIN_PHP=$(findBinaryByWhich php); fi
if [ -z "${BIN_COMPOSER}" ]; then BIN_COMPOSER=$(findBinaryByWhich composer); fi
GIT_BRANCH="${GIT_BRANCH:-master}"
RUN_AS_USERNAME=${RUN_AS_USERNAME:-}
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
            runDeploy
        ;;
        deployDirect)
            deployDirect
        ;;
        *)
            dockerComposeCmd "${@:1}"
        ;;
    esac
}

startFunction "${@:1}"
exit $?
