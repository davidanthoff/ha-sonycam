ARG BUILD_FROM
FROM ${BUILD_FROM}

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git unzip curl ca-certificates \
        python3 python3-paho-mqtt \
    && rm -rf /var/lib/apt/lists/*

# sonycam source only - the Sony SDK itself is supplied by the user at runtime
ARG SONYCAM_REPO=https://github.com/davidanthoff/sonycam
ARG SONYCAM_COMMIT=e72b000b6b77fec17a78525abc5f75a227bbb163
RUN git clone ${SONYCAM_REPO} /opt/sonycam-src \
    && git -C /opt/sonycam-src checkout ${SONYCAM_COMMIT} \
    && git -C /opt/sonycam-src rev-parse HEAD > /opt/sonycam-src.rev

COPY rootfs/ /
RUN chmod a+x /run.sh

RUN chmod a+x /wrapper.sh
CMD [ "/command/with-contenv", "bash", "/wrapper.sh" ]
