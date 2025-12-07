#!/usr/bin/env bashio
set -e

bashio::log.info "=== Démarrage du Bluetooth Audio Gateway ==="

# 1. Démarrer BlueALSA si le binaire existe
if [ -x "/usr/bin/bluealsa" ]; then
    bashio::log.info "Démarrage de BlueALSA..."
    
    # Arrêter tout processus bluealsa existant
    pkill -9 bluealsa 2>/dev/null || true
    sleep 1
    
    # Démarrer avec les profils audio
    /usr/bin/bluealsa --profile=a2dp-sink --profile=a2dp-source &
    BLUEALSA_PID=$!
    sleep 3
    
    if ps -p $BLUEALSA_PID >/dev/null 2>&1; then
        bashio::log.info "✅ BlueALSA démarré (PID: $BLUEALSA_PID)"
    else
        bashio::log.warning "⚠️  BlueALSA n'a pas démarré, tentative en mode debug..."
        /usr/bin/bluealsa --profile=a2dp-sink --verbose &
        sleep 2
    fi
else
    bashio::log.error "❌ Binaire BlueALSA non trouvé dans /usr/bin/bluealsa"
    bashio::log.info "Liste des fichiers bluealsa trouvés :"
    find / -name "*bluealsa*" -type f 2>/dev/null || true
fi

# 2. Vérifier les outils disponibles
bashio::log.info "=== Vérification des outils ==="
[ -x "/usr/bin/bluealsa-aplay" ] && bashio::log.info "✅ bluealsa-aplay: présent"
[ -x "/usr/bin/bluetoothctl" ] && bashio::log.info "✅ bluetoothctl: présent"

# 3. Démarrer l'API Flask (TOUJOURS)
bashio::log.info "=== Démarrage de l'API Web ==="
exec python3 /api/server.py