FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

COPY --from=openbao/openbao:2.7.3@sha256:ba4b133eb9586630024e71a617e66f37f29cc3534cdd46a6233e098ceded8dc9 /usr/bin/bao /usr/local/bin 

COPY kubernetes/bao-snapshot.sh /

RUN apk add --no-cache s3cmd && \
    chmod +x bao-snapshot.sh

CMD ["/bao-snapshot.sh"]
