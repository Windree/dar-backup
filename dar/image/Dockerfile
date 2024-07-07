FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt update && \
    apt install -y dar locales && \
    locale-gen en && \
    rm -rf /var/lib/apt/*
ENV LC_ALL=en_US.UTF8
ADD _ /
ENTRYPOINT ["/entrypoint.sh"]
