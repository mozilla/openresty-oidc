# syntax=docker/dockerfile:1
#
# openresty-oidc: OpenResty bundle with lua-resty-openidc preinstalled.
#
# Base: openresty/openresty:${OPENRESTY_VERSION}-${OPENRESTY_VARIANT}. When the
# default values are used, the base is openresty/openresty:1.29.2.5-alpine,
# which bundles nginx 1.29.2 with the CVE-2026-42945 and CVE-2026-9256
# (ngx_http_rewrite_module heap overflow) backports applied upstream.
#
# All versions, the runtime uid/gid, and label metadata are overridable via
# --build-arg so the same Dockerfile can produce future builds without edits.

ARG OPENRESTY_VERSION=1.29.2.5
ARG OPENRESTY_VARIANT=alpine

FROM openresty/openresty:${OPENRESTY_VERSION}-${OPENRESTY_VARIANT}

# Re-declare so these resolve in stages below FROM.
ARG OPENRESTY_VERSION
ARG OPENRESTY_VARIANT

ARG LUA_RESTY_OPENIDC_VERSION=1.7.6
ARG RUNTIME_USER=openresty
ARG RUNTIME_UID=101
ARG RUNTIME_GID=101

# Lua API version that luarocks targets. OpenResty's bundled LuaJIT is 5.1
# ABI-compatible, which matches the apk package name (luarocks5.1) and the
# installed binary (luarocks-5.1). Only change this if OpenResty ever moves
# off the 5.1 ABI.
ARG LUA_VERSION=5.1

# perl is kept at runtime because OpenResty's `resty` CLI is a Perl script
# (matches the existing image; operators may shell in and use `resty` for
# debugging). Everything in .build-deps is dropped after install.
RUN apk add --no-cache perl \
    && apk add --no-cache --virtual .build-deps \
        curl \
        gcc \
        luarocks${LUA_VERSION} \
        make \
        musl-dev \
        openssl-dev \
        unzip \
    && luarocks-${LUA_VERSION} \
        --tree /usr/local/openresty/luajit \
        --lua-dir=/usr/local/openresty/luajit \
        install lua-resty-openidc ${LUA_RESTY_OPENIDC_VERSION} \
    && apk del .build-deps

# Match the existing image's unprivileged runtime user. /var/run/openresty
# is where the upstream default nginx.conf and most tenant configs place
# nginx temp dirs (client_body_temp_path, proxy_temp_path, etc.), so it
# must be writable by the runtime user.
RUN addgroup -g ${RUNTIME_GID} -S ${RUNTIME_USER} \
    && adduser -S -D -H -u ${RUNTIME_UID} -G ${RUNTIME_USER} \
        -h /home/${RUNTIME_USER} -s /sbin/nologin ${RUNTIME_USER} \
    && mkdir -p /home/${RUNTIME_USER} /var/run/openresty \
    && chown -R ${RUNTIME_USER}:${RUNTIME_USER} \
        /home/${RUNTIME_USER} \
        /usr/local/openresty/nginx/logs \
        /usr/local/openresty/nginx/conf \
        /var/run \
        /var/run/openresty

# OCI labels. Override IMAGE_* args at build time to keep metadata accurate
# when the image source moves or when minting a new build number.
ARG IMAGE_TITLE="openresty-oidc"
ARG IMAGE_DESCRIPTION="OpenResty with lua-resty-openidc preinstalled."
ARG IMAGE_SOURCE="https://github.com/mozilla/openresty-oidc"
ARG IMAGE_VERSION="${OPENRESTY_VERSION}-0-${OPENRESTY_VARIANT}"

LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
      org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      openresty.version="${OPENRESTY_VERSION}" \
      lua_resty_openidc.version="${LUA_RESTY_OPENIDC_VERSION}"

USER ${RUNTIME_USER}

STOPSIGNAL SIGQUIT

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
