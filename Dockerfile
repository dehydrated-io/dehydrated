FROM alpine:latest

RUN apk add --update \
    bash \
    curl \
    openssl \
    && rm -rf /var/cache/apk/*

WORKDIR dehydrated
COPY . .

ENTRYPOINT ["bash", "dehydrated"]
