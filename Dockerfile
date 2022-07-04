ARG ALPINE_VERSION=3.11.5

FROM alpine:${ALPINE_VERSION}

ARG CREATE_DATE
ARG REVISION
ARG BUILD_VERSION

LABEL maintainer="psellars@gmail.com"

RUN apk add --no-cache \
    curl \
    git \
    openssh-client \
    rsync

ENV VERSION 0.64.0

WORKDIR /usr/local/src
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN wget \
  https://github.com/gohugoio/hugo/releases/download/v${VERSION}/hugo_${VERSION}_Linux-64bit.tar.gz

RUN wget \
  https://github.com/gohugoio/hugo/releases/download/v${VERSION}/hugo_${VERSION}_checksums.txt \
    && sed -i '/hugo_[0-9].*Linux-64bit.tar.gz/!d' \
       hugo_${VERSION}_checksums.txt \
    && sha256sum -cs hugo_${VERSION}_checksums.txt \
    && tar -xzvf hugo_"${VERSION}"_Linux-64bit.tar.gz \

    && mv hugo /usr/local/bin/hugo \

    && addgroup -Sg 1000 hugo \
    && adduser -SG hugo -u 1000 -h /src hugo

LABEL org.opencontainers.image.create_date=$CREATE_DATE
LABEL org.opencontainers.image.title="hugo_builder"
LABEL org.opencontainers.image.source="https://github.com/psellars/docker-container-security-lp"
LABEL org.opencontainers.image.revision=$REVISION 
LABEL org.opencontainers.image.version=$BUILD_VERSION 
LABEL org.opencontainers.image.licenses="Apache-2.0" 
LABEL hugo_version=$VERSION

USER hugo

WORKDIR /src

EXPOSE 1313

HEALTHCHECK --interval=10s --timeout=10s --start-period=15s \
  CMD hugo env || exit 1
