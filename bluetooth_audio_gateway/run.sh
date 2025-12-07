#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."
bashio::log.info "Ce module utilise les services Bluetooth et D-Bus du système hôte."

# === 1. CONFIGURATION D'ENVIRONNEMENT ===
# Utiliser le bus D-Bus système existant
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"

# === 2. VÉRIFICATION ET DÉMARRAGE DE BLUEALSA ===
bashio::log.info "Vérification de l'installation BlueALSA..."

if command -v bluealsa >/dev/null 2>&1; then
    BLUEALSA_PATH=$(command -v bluealsa)
    bashio::log.info "✅ BlueALSA trouvé : $BLUEALSA_PATH"
    
    # Vérifier si BlueALSA est déjà en cours d'exécution
    if ! pgrep -x "bluealsa" >/dev/null; then
        bashio::log.info "Démarrage du démon BlueALSA..."
        bluealsa --profile=a2dp-sink --profile=a2dp-source &
        BLUEALSA_PID=$!
        sleep 3
        
        if kill -0 $BLUEALSA_PID 2>/dev/null; then
            bashio::log.info "✅ BlueALSA démarré avec succès."
        else
            bashio::log.error "❌ Échec du démarrage de BlueALSA."
        fi
    else
        bashio::log.info "ℹ️  BlueALSA est déjà en cours d'exécution."
    fi
else
    bashio::log.error "❌ BlueALSA n'est pas installé. La construction de l'add-on a échoué."
    exit 1
fi

# === 3. VÉRIFICATION RAPIDE DES OUTILS ===
bashio::log.info "Outils disponibles :"
if command -v bluealsa-aplay >/dev/null 2>&1; then
    bashio::log.info "  - bluealsa-aplay : ✅"
fi
if command -v bluetoothctl >/dev/null 2>&1; then
    bashio::log.info "  - bluetoothctl : ✅"
fi

# === 4. DÉMARRAGE DE L'API FLASK ===
bashio::log.info "========================================"
bashio::log.info "🚀 Démarrage de l'API Flask sur le port 3000"
bashio::log.info "========================================"

if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi

exec python3 /api/server.py