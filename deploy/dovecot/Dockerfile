FROM tailscale/tailscale:stable

RUN echo "https://mirrors.aliyun.com/alpine/v3.22/main" > /etc/apk/repositories \
    && echo "https://mirrors.aliyun.com/alpine/v3.22/community" >> /etc/apk/repositories \
    && apk add --no-cache dovecot openssl

COPY dovecot.conf /etc/dovecot/dovecot.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod 0755 /entrypoint.sh

EXPOSE 993

ENTRYPOINT ["/entrypoint.sh"]
