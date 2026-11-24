ARG BASE_IMAGE=ubuntu@sha256:562111b88caa79c71391c0c4d3c2114a7d5c35915c20561fd893cb1e07929e6b
FROM ${BASE_IMAGE}

RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    ca-certificates \
    gcc \
    g++ \
    make \
    clang \
    python3 \
    python3-pil \
    libfribidi0 \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
