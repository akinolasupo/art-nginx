#!/bin/bash

# An entrypoint script for Nginx to allow custom setup before server starts

source functions.sh

export ART_BASE_URL

# Print on container startup information about Dockerfile location
printDockerFileLocation() {
    logger "Dockerfile for this image can found inside the container."
    logger "To view the Dockerfile: 'cat /docker/nginx-artifactory-pro/Dockerfile.nginx'."
}

copyExampleSSL () {
    logger "Copying auto generated SSL keys"

    [ -f /etc/pki/tls/private/example.key ] || errorExit "SSL is set, but SSL key (/etc/pki/tls/private/example.key) not found"
    [ -f /etc/pki/tls/certs/example.pem ] || errorExit "SSL is set, but SSL certificate (/etc/pki/tls/certs/example.pem) not found"

    logger "Copying..."
    mkdir -p $NGINX_DATA/ssl
    cp -v /etc/pki/tls/private/example.key $NGINX_DATA/ssl/ || errorExit "Failed copying /etc/pki/tls/private/example.key to $NGINX_DATA/ssl"
    cp -v /etc/pki/tls/certs/example.pem $NGINX_DATA/ssl/ || errorExit "Failed copying /etc/pki/tls/certs/example.pem to $NGINX_DATA/ssl"
}

setupSSL () {
    logger "SSL is set. Setting up SSL certificate and key"

    if [ "${SSL}" == "true" ]; then
        # Support only zero or two files in /etc/nginx/ssl to allow for auto resolve and config
        NUM_OF_FILES=$(ls -1 $NGINX_DATA/ssl/ | wc -l)
        if [ $NUM_OF_FILES -eq 0 ]; then
            copyExampleSSL
        elif [ $NUM_OF_FILES -eq 2 ]; then
            # Try to find SSL key and certificate
            local SSL_KEY=$(ls $NGINX_DATA/ssl/*.key 2> /dev/null)
            local SSL_CRT=$(ls $NGINX_DATA/ssl/*.crt 2> /dev/null)
            local SSL_PEM=$(ls $NGINX_DATA/ssl/*.pem 2> /dev/null)

            [ -f "${SSL_KEY}" ] && logger "Found SSL_KEY $SSL_KEY"
            [ -f "${SSL_CRT}" ] && logger "Found SSL_CRT $SSL_CRT"
            [ -f "${SSL_PEM}" ] && logger "Found SSL_PEM $SSL_PEM"

            # Validate a private key exists
            [ -f "${SSL_KEY}" ] || errorExit "SSL key file ${SSL_KEY} does not exist"

            # Get the certificate (.crt or .pem)
            local SSL_CERTIFICATE="${SSL_CRT}${SSL_PEM}"

            # Validate certificate file exists
            [ -f "${SSL_CERTIFICATE}" ] || errorExit "SSL certificate ${SSL_CERTIFICATE} does not exist"

            logger "Updating $NGINX_ART_CONF with $SSL_KEY and $SSL_CERTIFICATE"
            sed -i "s,^ssl_certificate .*,ssl_certificate  ${SSL_CERTIFICATE};,g" $NGINX_ART_CONF || errorExit "Failed setting $SSL_CERTIFICATE in $NGINX_ART_CONF"
            sed -i "s,^ssl_certificate_key .*,ssl_certificate_key  ${SSL_KEY};,g" $NGINX_ART_CONF || errorExit "Failed setting $SSL_KEY in $NGINX_ART_CONF"
        else
            local LIST_OF_FILES=$(ls ${NGINX_DATA}/ssl/ | tr '\n' ' ')
            errorExit "$NGINX_DATA/ssl/ must contain 2 files exactly (.key file and .pem or .crt). Found: ${LIST_OF_FILES}"
        fi
    else
        logger "$NGINX_DATA/ssl does not exist. Creating it"
        mkdir -p $NGINX_DATA/ssl || errorExit "Creation of $NGINX_DATA/ssl failed"
        copyExampleSSL
    fi
}

setupDataDirs () {
    logger "Setting up directories if missing"
    [ -d ${NGINX_DATA}/conf.d ] || mkdir -p ${NGINX_DATA}/conf.d || errorExit "Failed creating $NGINX_DATA/conf.d"
    [ -d ${NGINX_DATA}/ssl ]    || mkdir -p ${NGINX_DATA}/ssl    || errorExit "Failed creating $NGINX_DATA/ssl"
    [ -d ${NGINX_DATA}/logs ]   || mkdir -p ${NGINX_DATA}/logs   || errorExit "Failed creating $NGINX_DATA/logs"
}

setDefaultReverseProxyConfig () {
    # Update the reverse proxy configuration
    logger "Updating the reverse proxy configuration to default"
    local key=$1
    local type=$2
    local ssl_sertificate=$(grep "ssl_certificate " /etc/nginx/conf.d/artifactory.conf | awk '{print $2}' | tr -d ';')
    local ssl_certificate_key=$(grep "ssl_certificate_key " /etc/nginx/conf.d/artifactory.conf | awk '{print $2}' | tr -d ';')
    local artifactory_app_context=$(grep "server_name " /etc/nginx/conf.d/artifactory.conf | awk '{print $3}' | tr -d ';')

    payload=$(cat <<END_PAYLOAD
{
"key":"${key}",
"webServerType":"${type}",
"artifactoryAppContext":"${artifactory_app_context}",
"publicAppContext":"${artifactory_app_context}",
"serverName":"arti.local",
"serverNameExpression":"*.jfrog.com",
"artifactoryServerName":"artifactory-node1",
"artifactoryPort":8081,
"sslCertificate":"${ssl_sertificate}",
"sslKey":"${ssl_certificate_key}",
"dockerReverseProxyMethod":"SUBDOMAIN",
"useHttps":true,
"useHttp":true,
"sslPort":443,
"httpPort":80
}
END_PAYLOAD
)
    curl -s -X POST -H "Content-Type: application/json" -u$ART_LOGIN:$ART_PASSWORD -d "${payload}" ${ART_BASE_URL}/api/system/configuration/webServer > /dev/null
    if [ $? -eq 0 ]; then
        logger "Reverse proxy configuration updated successfully"
    else
        logger "WARNING: Reverse proxy configuration setup failed"
    fi
}

checkIfNeedToSetReverseProxy () {
    # Override when needed: key (nginx/apache), type (NGINX/APACHE)
    local key="nginx"
    local type="NGINX"
    local status=$(curl -s -X GET -u$ART_LOGIN:$ART_PASSWORD ${ART_BASE_URL}/api/system/configuration/reverseProxy/${key} | grep status | awk '{print $3}' | sed -e "s|,||g")
    if [ -n "${status}" ] && [[ "${status}" =~ 404|400 ]]; then
        setDefaultReverseProxyConfig ${key} ${type}
    else
        logger "Reverse proxy configuration already set. Skipping"
    fi
}

# Setup the artifactory.conf if needed
setupArtifactoryConf () {
    if [ ! -f "$NGINX_ART_CONF" ]; then
        logger "Unable to find Artifactory configuration ($NGINX_ART_CONF). Copying a default one"
        cp -f /${NGINX_ART_CONF_NAME} ${NGINX_ART_CONF} || errorExit "Copying /${NGINX_ART_CONF_NAME} to ${NGINX_ART_CONF} failed"

        # Set a default "Artifactory" host
        sed -i "s/artifactory-node1/artifactory/g" ${NGINX_ART_CONF} || errorExit "Updating ${NGINX_ART_CONF} failed"
    else
        logger "Artifactory configuration already in $NGINX_ART_CONF"
    fi
}

####### Main #######

logger "Preparing to run Nginx in Docker"

printDockerFileLocation
setupDataDirs
setupArtifactoryConf
setupSSL

if [ "${SKIP_AUTO_UPDATE_CONFIG}" == "true" ]; then
    logger "SKIP_AUTO_UPDATE_CONFIG is set. Not starting auto configuration script"
else
    # Run the auto update script
    logger "Starting updateConf.sh in the background"
    ./updateConf.sh 2>&1 &
fi

# Run Nginx
logger "Starting nginx daemon..."

exec nginx -g 'daemon off;'
