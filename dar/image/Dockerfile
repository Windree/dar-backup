FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt update && \
    apt install -y dar locales && \
    locale-gen en && \
    rm -rf /var/lib/apt/lists/* && \
    ENV LC_ALL=en_US.UTF8   
ENTRYPOINT ["/entrypoint.sh"]
