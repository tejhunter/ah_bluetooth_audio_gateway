#!/usr/bin/env bashio

# Charger la configuration de l'add-on
DEVICE_ADDRESS=$(bashio::config 'device_address')

# Démarrer le service D-Bus (nécessaire pour BlueZ)
bashio::log.info "Démarrage de D-Bus..."
dbus-daemon --system --nofork &
sleep 2

# Démarrer le service Bluetooth
bashio::log.info "Démarrage du service Bluetooth..."
bluetoothd &
sleep 2

# Activer l'adaptateur Bluetooth
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up
hciconfig hci0 piscan

# Si une adresse MAC est configurée, tenter la connexion
if [ ! -z "$DEVICE_ADDRESS" ]; then
    bashio::log.info "Tentative de connexion à $DEVICE_ADDRESS..."
        echo "connect $DEVICE_ADDRESS" | bluetoothctl
            sleep 5
            fi

            # Démarrer le serveur API Python
            bashio::log.info "Démarrage du serveur API..."
            python3 /api/server.py &

            # Garder le conteneur en vie
            bashio::log.info "Add-on Bluetooth Audio Gateway démarré!"
            tail -f /dev/null