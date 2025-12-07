ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:latest
FROM ${BUILD_FROM}

LABEL \
    io.hass.name="Bluetooth Audio Gateway" \
    io.hass.description="Bluetooth audio bridge for Home Assistant" \
    io.hass.type="addon"

# 1. Installation des dépendances de base (SANS compilation)
RUN apk update && apk add --no-cache \
    bluez \
    bluez-deprecated \
    bluez-libs \
    bluez-openrc \
    dbus \
    python3 \
    py3-pip \
    py3-dbus \
    py3-gobject3 \
    alsa-utils \
    alsa-lib \
    curl \
    bash

# 2. ÉTAPE CRITIQUE : Compilation de BlueALSA avec vérifications
# 2a. Installation de TOUTES les dépendances de compilation
RUN apk add --no-cache --virtual .build-deps \
    git \
    make \
    gcc \
    musl-dev \
    autoconf \
    automake \
    libtool \
    pkgconf \
    alsa-lib-dev \
    dbus-dev \
    glib-dev \
    bluez-dev \
    libbsd-dev \
    sbc-dev

# 2b. Téléchargement des sources
RUN cd /tmp && \
    git clone --depth=1 --branch=v4.2.0 https://github.com/Arkq/bluez-alsa.git

# 2c. Compilation et installation
RUN cd /tmp/bluez-alsa && \
    autoreconf --install && \
    mkdir -p build && cd build && \
    ../configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --enable-aac \
        --enable-ofono \
        --enable-debug \
        --enable-systemd && \
    make -j$(nproc) && \
    make install && \
    # Installation des fichiers de configuration ALSA
    mkdir -p /etc/alsa/conf.d && \
    ln -sf /usr/share/alsa/alsa.conf.d/20-bluealsa.conf /etc/alsa/conf.d/

# 2d. VÉRIFICATION OBLIGATOIRE de la compilation
RUN ls -la /usr/bin/bluealsa* && \
    /usr/bin/bluealsa --version || (echo "ÉCHEC DE LA COMPILATION" && exit 1)

# 2e. Nettoyage des outils de compilation
RUN apk del .build-deps && \
    rm -rf /tmp/bluez-alsa

# 3. Installation des utilitaires CLI (optionnels mais utiles)
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && apk add --no-cache bluez-alsa-utils

# 4. Dépendances Python pour l'API web
RUN apk add --no-cache \
    py3-flask \
    py3-flask-cors

# Copie des fichiers de l'add-on
COPY run.sh /
COPY api /api/
COPY www /www/

RUN chmod a+x /run.sh
EXPOSE 3000
CMD [ "/run.sh" ]