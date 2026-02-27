# ---------------------------------------------------------------------------
# Stage 1 – build the oli binary using Rust on musl (static linking)
# ---------------------------------------------------------------------------
FROM rust:alpine AS oli-builder

RUN apk add --no-cache musl-dev openssl-dev openssl-libs-static pkgconfig perl make

# Install oli – the OpenDAL command-line interface used to upload snapshots
# to any supported object-storage backend (S3, GCS, Azure Blob, …).
RUN cargo install oli

# ---------------------------------------------------------------------------
# Stage 2 – final image
# ---------------------------------------------------------------------------
FROM alpine

ARG BAO_VERSION=2.5.0
ARG TARGETOS
ARG TARGETARCH

COPY kubernetes/bao-snapshot.sh /

RUN ARCH="${TARGETARCH}" && \
    if [ "${ARCH}" = "amd64" ]; then ARCH="x86_64"; fi && \
    wget https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/bao_${BAO_VERSION}_Linux_${ARCH}.tar.gz && \
    tar xzf bao_${BAO_VERSION}_Linux_${ARCH}.tar.gz && \
    mv bao /usr/local/bin && \
    rm -f bao_*.tar.gz && \
    apk add --no-cache ca-certificates && \
    sed -i 's/\r//' /bao-snapshot.sh && \
    chmod +x /bao-snapshot.sh

# Copy the statically-linked oli binary from the builder stage
COPY --from=oli-builder /usr/local/cargo/bin/oli /usr/local/bin/oli

CMD ["/bao-snapshot.sh"]
