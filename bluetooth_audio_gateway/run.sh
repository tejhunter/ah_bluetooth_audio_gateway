#!/usr/bin/env bashio

# Arrêter le script en cas d'erreur
set -e

# Charger la configuration de l'add-on
DEVICE_ADDRESS=$(bashio::config 'device_address')

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."

# Démarrer le service D-Bus (nécessaire pour BlueZ)
bashio::log.info "Démarrage de D-Bus..."
dbus-daemon --system --nofork &
DBUS_PID=$!
sleep 3

# Démarrer le service Bluetooth
bashio::log.info "Démarrage du service Bluetooth..."
bluetoothd --debug &
BLUETOOTH_PID=$!
sleep 3

# Activer l'adaptateur Bluetooth
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || bashio::log.error "Échec de l'activation de hci0"
hciconfig hci0 piscan || bashio::log.warning "Échec du mode piscan"

# Si une adresse MAC est configurée, tenter la connexion
if [ -n "$DEVICE_ADDRESS" ]; then
    bashio::log.info "Tentative de connexion à $DEVICE_ADDRESS..."
    
    # S'assurer que l'appareil est appairé et fait confiance
    echo -e "trust $DEVICE_ADDRESS\nconnect $DEVICE_ADDRESS" | bluetoothctl
    sleep 5
    
    # Vérifier la connexion
    if hciconfig hci0 | grep -q "UP RUNNING"; then
        bashio::log.info "Connexion Bluetooth établie."
    else
        bashio::log.warning "La connexion Bluetooth pourrait avoir échoué."
    fi
fi

# Démarrer le serveur API Python
bashio::log.info "Démarrage du serveur API..."
exec python3 /api/server.py
