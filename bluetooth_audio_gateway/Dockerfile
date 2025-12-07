ARG BUILD_FROM
FROM ${BUILD_FROM}

# Définit les métadonnées (optionnel)
LABEL \
    io.hass.name="Bluetooth Audio Gateway" \
    io.hass.description="Bluetooth audio bridge for Home Assistant" \
    io.hass.type="addon"

# Installation des dépendances CRITIQUES
RUN apk add --no-cache \
    bluez \
    bluez-deprecated \
    bluez-libs \
    bluez-alsa-utils \
    dbus \
    python3 \
    py3-pip \
    py3-dbus \           
    py3-gobject3 \       
    alsa-utils \
    pulseaudio \
    pulseaudio-bluez \
    curl \
    bash \
    git \
    gcc \
    musl-dev \
    python3-dev \        
    linux-headers        

# Installation des dépendances Python pour l'API web VIA APK (et non pip)
RUN apk add --no-cache \
    py3-flask \
    py3-flask-cors

# Copie les fichiers de l'add-on
COPY run.sh /
COPY api /api/
COPY www /www/

# Rend le script exécutable
RUN chmod a+x /run.sh

# Le port exposé (doit correspondre à config.yaml)
EXPOSE 3000

# Commande de démarrage
CMD [ "/run.sh" ]