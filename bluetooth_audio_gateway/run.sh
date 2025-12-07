#!/usr/bin/env bashio

# Arrêter le script en cas d'erreur
set -e

# Charger la configuration de l'add-on
DEVICE_ADDRESS=$(bashio::config 'device_address')

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."

# IMPORTANT : D-Bus et bluetoothd sont déjà en cours d'exécution sur l'hôte.
# Nous n'avons PAS besoin de les redémarrer. Attendre qu'ils soient prêts.
sleep 5

# Activer l'adaptateur Bluetooth hci0 et le rendre visible
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || {
    bashio::log.error "Échec de l'activation de hci0. Vérifiez les permissions Bluetooth."
    exit 1
}
hciconfig hci0 piscan || bashio::log.warning "Le mode 'piscan' a peut-être échoué (peut être normal)."

# Si une adresse MAC est configurée, tenter la connexion
if [ -n "${DEVICE_ADDRESS}" ]; then
    bashio::log.info "Tentative de connexion à ${DEVICE_ADDRESS}..."
    
    # S'assurer que l'appareil est appairé/trusté, puis se connecter
    echo -e "trust ${DEVICE_ADDRESS}\nconnect ${DEVICE_ADDRESS}" | bluetoothctl
    sleep 8
    
    # Vérifier l'état de la connexion
    CONNECTION_STATUS=$(echo "info ${DEVICE_ADDRESS}" | bluetoothctl | grep -c "Connected: yes")
    if [ "${CONNECTION_STATUS}" -eq 1 ]; then
        bashio::log.info "Connexion Bluetooth établie avec succès."
    else
        bashio::log.warning "La connexion a peut-être échoué. Vérifiez que l'appareil est allumé et appairé."
    fi
fi

# Démarrer BlueALSA daemon (nécessaire pour la lecture audio Bluetooth)
bashio::log.info "Démarrage du daemon BlueALSA..."

# Arrêter tout processus bluealsa existant pour un démarrage propre
pkill -9 bluealsa 2>/dev/null || true
sleep 2

# Démarrer bluealsa avec les paramètres optimisés pour Home Assistant OS
# L'option -p a2dp-sink permet le profil audio A2DP (haute qualité)
bluealsa -p a2dp-sink -i hci0 &
BLUEALSA_PID=$!
sleep 3

# Vérification robuste du démarrage
if ps -p $BLUEALSA_PID > /dev/null 2>&1; then
    bashio::log.info "✅ BlueALSA daemon actif (PID: $BLUEALSA_PID)"
    
    # Vérifier que le socket BlueALSA est créé
    if [ -S "/var/run/bluealsa/hci0" ] || [ -S "/tmp/bluealsa.socket" ]; then
        bashio::log.info "✅ Socket BlueALSA détecté"
    else
        bashio::log.warning "⚠️  Socket BlueALSA non trouvé. Essai avec spécification manuelle..."
        # Redémarrer avec socket explicite
        pkill -9 bluealsa 2>/dev/null || true
        bluealsa -p a2dp-sink -i hci0 -S /tmp/bluealsa.socket &
        sleep 3
    fi
else
    bashio::log.error "❌ BlueALSA daemon n'a pas pu démarrer"
    bashio::log.warning "Tentative avec debug activé..."
    bluealsa -p a2dp-sink -i hci0 -v &
    sleep 5
fi

# Vérifier les processus audio
bashio::log.info "Processus audio en cours d'exécution :"
ps aux | grep -E "(bluealsa|bluez|pulse)" | grep -v grep || true

# Démarrer le serveur API Python
bashio::log.info "Démarrage du serveur API Flask..."

# Vérifier que le fichier existe
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi

# Lancer le serveur Flask (remplace le processus actuel)
exec python3 /api/server.py