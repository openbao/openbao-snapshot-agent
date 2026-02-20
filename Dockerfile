FROM alpine

ARG BAO_VERSION=2.5.0

ARG TARGETOS
ARG TARGETARCH

COPY kubernetes/bao-snapshot.sh /

RUN if [[ "$TARGETARCH" == "amd64" ]]; then \
        TARGETARCH="x86_64"; \
    fi && \
    wget https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/bao_${BAO_VERSION}_Linux_${TARGETARCH}.tar.gz && \
    tar xzf bao_${BAO_VERSION}_Linux_${TARGETARCH}.tar.gz && \ 
    mv bao /usr/local/bin && rm  bao*tar.gz  && \
    apk add s3cmd && chmod +x bao-snapshot.sh

CMD ["/bao-snapshot.sh"]
