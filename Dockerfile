FROM alpine:3.10.3

RUN apk --update --no-cache add \
  bash

ADD assets /opt/resource
RUN chmod +x /opt/resource/*
