FROM docker.bintray.io/jfrog/art-nginx:1.11.10

MAINTAINER akinolasupo@gmail.com

# Copy needed files
COPY nginx.conf /etc/nginx/nginx.conf
COPY functions.sh /
COPY entrypoint-nginx.sh /
COPY updateConf.sh /
COPY artifactory-pro.conf /artifactory.conf

ENV NGINX_DATA /var/opt/jfrog/nginx

# Update the OS (exclude nginx packages)
RUN mkdir -p /etc/pki/tls/private && mkdir -p /etc/pki/tls/certs && \
    openssl req -nodes -x509 -newkey rsa:4096 -keyout /etc/pki/tls/private/example.key \
        -out /etc/pki/tls/certs/example.pem -days 3650 \
        -subj "/C=US/ST=California/L=SantaClara/O=IT/CN=arts.k8s.opsmonks.com" && \
    chmod +x /entrypoint-nginx.sh /updateConf.sh

# Prepare data directory and soflinks to it
RUN mkdir -p ${NGINX_DATA} && \
    mkdir -p ${NGINX_DATA}/logs && \
    mkdir -p ${NGINX_DATA}/conf.d && \
    mkdir -p ${NGINX_DATA}/ssl && \
    mkdir -p /var/cache/nginx && \
    mv /var/log/nginx /var/log/nginx.tmp && \
    mv /etc/nginx/conf.d /etc/nginx/conf.d.tmp && \
    ln -s ${NGINX_DATA}/logs /var/log/nginx && \
    ln -s ${NGINX_DATA}/conf.d /etc/nginx/conf.d && \
    ln -s ${NGINX_DATA}/ssl /etc/nginx/ssl && \
    mv -v /var/log/nginx.tmp/* /var/log/nginx/ && rm -rfv /var/log/nginx.tmp && \
    mv -v /etc/nginx/conf.d.tmp/* /etc/nginx/conf.d/ && rm -rfv /etc/nginx/conf.d.tmp && \
    setcap CAP_NET_BIND_SERVICE=+eip /usr/sbin/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx. ${NGINX_DATA} /var/cache/nginx /var/run/nginx.pid


# The user that will run the container
USER nginx

# Single mount for all data and config
VOLUME ${NGINX_DATA}

# Expose web ports
EXPOSE 80 443

# Run the nginx server from the entrypoint script
ENTRYPOINT ["/entrypoint-nginx.sh"]
