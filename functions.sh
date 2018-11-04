#!/bin/bash

NGINX_DATA=/var/opt/jfrog/nginx
NGINX_ART_CONF_NAME=artifactory.conf
NGINX_ART_CONF=$NGINX_DATA/conf.d/$NGINX_ART_CONF_NAME

# Artifactory login
: ${ART_LOGIN:=_internal}
# Artifactory password
: ${ART_PASSWORD:=b6a50c8a15ece8753e37cbe5700bf84f}
# Artifactory base url (in HA, needs to be of the primary node)
: ${ART_BASE_URL:=http://artifactory-node1:8081/artifactory}

# Interval in seconds to check for new configuration on artifactory
CHECK_INTERVAL=10

logger() {
    DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
    if [ -z "$CONTEXT" ]
    then
        CONTEXT=$(caller)
    fi
    MESSAGE=$1
    CONTEXT_LINE=$(echo "$CONTEXT" | awk '{print $1}')
    CONTEXT_FILE=$(echo "$CONTEXT" | awk -F"/" '{print $NF}')
    printf "%s %05s %s %s\n" "$DATE_TIME" "[$CONTEXT_LINE" "$CONTEXT_FILE]" "$MESSAGE"
    CONTEXT=
}

error () {
    logger "ERROR: $1"
}

errorExit () {
    error "$1"; echo
    exit 1
}

warn () {
    logger "WARNING: $1"
}

curlAuth () {
    if [ -z "$ART_API_KEY" ]; then
        echo "curl -u$ART_LOGIN:$ART_PASSWORD"
    else
        echo "curl -H \"X-JFrog-Art-Api:$ART_API_KEY\""
    fi
}

waitForPrimaryNode () {
    logger "Waiting for primary node $ART_BASE_URL"
    local arguments=" --output /dev/null --silent --head --fail $ART_BASE_URL/api/system/ping"
    until $(eval curl $arguments)
    do
        echo -n "."
        sleep $CHECK_INTERVAL
    done
    echo
    logger "Primary node is up!"
}
