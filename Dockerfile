FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y curl jq xz-utils git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /zig

RUN curl -LO https://ziglang.org/builds/zig-x86_64-linux-0.15.0-dev.669+561ab59ce.tar.xz && \
    tar -xf zig-x86_64-linux-0.15.0-dev.669+561ab59ce.tar.xz && \
    rm zig-x86_64-linux-0.15.0-dev.669+561ab59ce.tar.xz && \
    mv zig-x86_64-linux-0.15.0-dev.669+561ab59ce zig

ENV PATH="/zig/zig:${PATH}"

CMD ["zig", "version"]
