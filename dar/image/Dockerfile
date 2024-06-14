FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt update && \
    apt install -y dar && \
    rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["dar"]
