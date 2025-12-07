#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway (BlueALSA)..."
sleep 2

# === 1. CONFIGURATION DU PATH POUR TROUVER LES BINAIRES ===
# Ajout des chemins standards pour les binaires système
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# === 2. UTILISATION DU DBUS SYSTÈME DÉJÀ PRÉSENT ===
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
bashio::log.info "Utilisation du bus D-Bus système existant..."

if [ ! -S "$DBUS_SYSTEM_BUS_ADDRESS" ]; then
    bashio::log.warning "⚠️  Socket D-Bus principal non trouvé. Recherche d'alternatives..."
    if [ -S "/var/run/dbus/system_bus_socket" ]; then
        export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"
        bashio::log.info "Socket D-Bus trouvé sur /var/run/dbus/system_bus_socket"
    else
        bashio::log.error "❌ Aucun socket D-Bus système trouvé."
        exit 1
    fi
fi

# === 3. VÉRIFICATION ET DÉMARRAGE SERVICE BLUETOOTH ===
bashio::log.info "Vérification de l'installation Bluetooth..."

# Vérifier si bluetoothd existe avec chemin complet
BLUETOOTHD_PATH=""
if [ -x "/usr/sbin/bluetoothd" ]; then
    BLUETOOTHD_PATH="/usr/sbin/bluetoothd"
elif [ -x "/usr/bin/bluetoothd" ]; then
    BLUETOOTHD_PATH="/usr/bin/bluetoothd"
else
    # Dernière tentative : chercher dans le PATH
    BLUETOOTHD_PATH=$(which bluetoothd 2>/dev/null || echo "")
fi

if [ -z "$BLUETOOTHD_PATH" ]; then
    bashio::log.error "❌ bluetoothd non trouvé. Vérifiez l'installation du paquet 'bluez'."
    bashio::log.info "Tentative d'installation de bluez-deprecated..."
    if apk add --no-cache bluez-deprecated 2>/dev/null; then
        BLUETOOTHD_PATH=$(which bluetoothd)
        bashio::log.info "✅ bluez-deprecated installé avec succès"
    else
        bashio::log.error "❌ Échec de l'installation de bluez-deprecated"
        exit 1
    fi
fi

bashio::log.info "Démarrage du démon Bluetooth (bluetoothd) depuis $BLUETOOTHD_PATH"
$BLUETOOTHD_PATH --nodetach &
BLUETOOTHD_PID=$!
sleep 3

# === 4. ACTIVATION ADAPTATEUR BLUETOOTH ===
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || {
    bashio::log.error "Échec de l'activation de hci0. Vérifiez les permissions Bluetooth."
    exit 1
}
hciconfig hci0 piscan || bashio::log.warning "Mode 'piscan' non critique."
sleep 2

# === 5. VÉRIFICATION ET DÉMARRAGE DU DÉMON BLUEALSA ===
bashio::log.info "Vérification de l'installation BlueALSA..."

# Vérifier si bluealsa existe avec chemin complet
BLUEALSA_PATH=""
if [ -x "/usr/bin/bluealsa" ]; then
    BLUEALSA_PATH="/usr/bin/bluealsa"
elif [ -x "/usr/local/bin/bluealsa" ]; then
    BLUEALSA_PATH="/usr/local/bin/bluealsa"
else
    # Chercher dans le PATH
    BLUEALSA_PATH=$(which bluealsa 2>/dev/null || echo "")
fi

if [ -z "$BLUEALSA_PATH" ]; then
    bashio::log.error "❌ bluealsa non trouvé. La compilation depuis les sources a peut-être échoué."
    bashio::log.info "Vérification des fichiers BlueALSA installés..."
    find /usr -name "bluealsa*" -type f 2>/dev/null | head -10 | while read file; do
        bashio::log.info "Fichier trouvé: $file"
    done
    exit 1
fi

bashio::log.info "Démarrage du démon BlueALSA depuis $BLUEALSA_PATH"
$BLUEALSA_PATH --profile=a2dp-sink --profile=a2dp-source &
BLUEALSA_PID=$!
sleep 3

# Vérification du démarrage
if pgrep -x "bluealsa" > /dev/null; then
    bashio::log.info "✅ BlueALSA est en cours d'exécution."
else
    bashio::log.error "❌ BlueALSA n'a pas démarré correctement."
    # Afficher des informations de débogage
    bashio::log.info "Tentative de démarrage en mode debug..."
    $BLUEALSA_PATH --profile=a2dp-sink --verbose &
    sleep 2
    if ! pgrep -x "bluealsa" > /dev/null; then
        bashio::log.error "❌ Échec même en mode debug."
        exit 1
    fi
fi

# === 6. VÉRIFICATION DES PÉRIPHÉRIQUES BLUEALSA ===
bashio::log.info "Vérification de l'état BlueALSA..."
if command -v bluealsa-aplay &> /dev/null; then
    bashio::log.info "Liste des périphériques détectés par BlueALSA:"
    bluealsa-aplay --list-devices 2>/dev/null || bashio::log.warning "Aucun périphérique pour l'instant."
else
    bashio::log.warning "bluealsa-aplay non trouvé."
    # Chercher le binaire
    BLUEALSA_APLAY_PATH=$(which bluealsa-aplay 2>/dev/null || find /usr -name "bluealsa-aplay" -type f 2>/dev/null | head -1)
    if [ -n "$BLUEALSA_APLAY_PATH" ]; then
        bashio::log.info "bluealsa-aplay trouvé à: $BLUEALSA_APLAY_PATH"
        export PATH="$(dirname $BLUEALSA_APLAY_PATH):$PATH"
    fi
fi

# === 7. CONFIGURATION AUDIO ===
bashio::log.info "Configuration de l'environnement audio..."
export ALSA_PCM_CARD="bluealsa"

# === 8. DÉMARRAGE SERVEUR API ===
bashio::log.info "Démarrage du serveur API Flask..."
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi

# Log final
bashio::log.info "========================================"
bashio::log.info "✅ Bluetooth Audio Gateway initialisé"
bashio::log.info "✅ Backend audio : BlueALSA"
bashio::log.info "✅ API disponible sur le port 3000"
bashio::log.info "========================================"

exec python3 /api/server.py