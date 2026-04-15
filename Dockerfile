# Dockerfile.test
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    systemd sudo curl wget git iproute2 \
    && rm -rf /var/lib/apt/lists/*

COPY . /opt/bootstrap/
WORKDIR /opt/bootstrap

# Roda com trace
CMD ["bash", "-x", "./bootstrap.sh"]
