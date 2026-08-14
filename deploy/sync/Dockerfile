FROM tailscale/tailscale:stable

USER root
RUN echo "https://mirrors.aliyun.com/alpine/v3.22/main" > /etc/apk/repositories \
    && echo "https://mirrors.aliyun.com/alpine/v3.22/community" >> /etc/apk/repositories \
    && apk add --no-cache imapsync util-linux ca-certificates

COPY run-sync-loop.sh /app/run-sync-loop.sh
RUN chmod 0755 /app/run-sync-loop.sh

ENTRYPOINT ["/app/run-sync-loop.sh"]
