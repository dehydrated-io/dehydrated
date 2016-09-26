FROM alpine:latest
RUN apk add --update --progress \
        git \
        openssl \
        curl \
        bash
RUN cd / \
    && git clone https://github.com/lukas2511/dehydrated.git
ENTRYPOINT [ "/dehydrated/dehydrated" ]
