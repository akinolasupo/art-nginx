#!/bin/bash

# Script to automatically update Nginx reverse proxy configuration

source functions.sh

# Path to nginx conf inside the docker image
NGINX_CONF=/etc/nginx/conf.d/artifactory.conf

getReverseProxySnippet () {
    local response
    # Yes we separate declaration and assignment, if not, $? will not be properly set to the result of the curl
    local curl=$(curlAuth)
    local arguments=" --show-error --silent --fail $ART_BASE_URL/api/system/configuration/reverseProxy/nginx"
    response=$( (eval $curl $arguments) 2>&1)
    local responseStatus=$?

    if [ $responseStatus -ne 0 ]; then
        echo "ERROR"
    else
        echo "$response"
    fi
}

updateNginxConfIfNeeded () {
    local reverseProxyConf=$(getReverseProxySnippet)
    if [ "$reverseProxyConf" != "ERROR" ] && [ ! -z "$reverseProxyConf" ]; then
        local diffWithCurrentConf=$(diff -b ${NGINX_CONF} <(echo "$reverseProxyConf"))
        if [ -n "$diffWithCurrentConf" ]
        then
            logger "Artifactory config changed!"
            logger "Diff:"
            echo -e "$diffWithCurrentConf"
            echo; logger "Updating $NGINX_CONF"
            local savedConf=$(cat ${NGINX_CONF})
            echo "$reverseProxyConf" > ${NGINX_CONF}

            logger "Reloading Nginx configuration"
            /etc/init.d/nginx reload
            if [ $? -ne 0 ]; then
                error "Something went wrong after loading new config, restoring the previous conf"
                echo "$savedConf" > ${NGINX_CONF}
            fi
        fi
    fi
}

####### Main #######

# Check every CHECK_INTERVAL seconds for a diff between file conf and the one we get from artifactory
while [ true ]
do
    updateNginxConfIfNeeded
    sleep $CHECK_INTERVAL
done
