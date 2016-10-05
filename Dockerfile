FROM alpine:latest

RUN apk add --update \
    bash \
    curl \
    openssl \
    && rm -rf /var/cache/apk/*

COPY . .

ENTRYPOINT ["bash", "dehydrated"]
