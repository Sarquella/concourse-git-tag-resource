FROM alpine:3.13.2

RUN apk --update --no-cache add \
  bash \
  jq \
  git \
  openssh-client

ADD assets /opt/resource
RUN chmod +x /opt/resource/*
