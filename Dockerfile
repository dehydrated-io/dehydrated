FROM alpine:latest
RUN apk add --update --progress \
        git \
        openssl \
        curl \
        bash
RUN cd / \
    && mkdir -p /var/www/dehydrated \
    && git clone https://github.com/lukas2511/dehydrated.git
ENTRYPOINT [ "/dehydrated/dehydrated" ]
