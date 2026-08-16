FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

ARG BAO_VERSION=2.6.1
ARG TARGETARCH

COPY kubernetes/bao-snapshot.sh /

RUN if [[ "$TARGETARCH" == "amd64" ]]; then \
        TARGETARCH="x86_64"; \
    fi && \
    wget "https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/openbao_${BAO_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    wget "https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/checksums.txt" && \
    grep "openbao_${BAO_VERSION}_linux_${TARGETARCH}\.tar\.gz$" checksums.txt | sha256sum -c - && \
    tar xzf "openbao_${BAO_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    mv bao /usr/local/bin && \
    rm "openbao_${BAO_VERSION}_linux_${TARGETARCH}.tar.gz" checksums.txt && \
    apk add --no-cache s3cmd && \
    chmod +x bao-snapshot.sh

CMD ["/bao-snapshot.sh"]
