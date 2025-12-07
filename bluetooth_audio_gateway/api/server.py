from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import subprocess
import json
import os
import time

app = Flask(__name__, static_folder='/www')
CORS(app)

# Route pour servir la page d'accueil (index.html)
@app.route('/')
def serve_index():
    return send_from_directory('/www', 'index.html')

# Route pour servir les fichiers statiques (CSS, JS, etc.)
@app.route('/<path:filename>')
def serve_static(filename):
    return send_from_directory('/www', filename)

# ---------- API Bluetooth ----------
@app.route('/api/status', methods=['GET'])
def get_status():
    """Endpoint de test pour vérifier que le serveur fonctionne."""
    return jsonify({'status': 'ok', 'service': 'Bluetooth Audio Gateway'})

def get_device_details(mac_address):
    """Récupère les informations détaillées d'un appareil Bluetooth via bluetoothctl."""
    try:
        cmd = f"echo 'info {mac_address}' | bluetoothctl"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        output = result.stdout

        details = {
            'address': mac_address,
            'connected': 'Connected: yes' in output,
            'paired': 'Paired: yes' in output,
            'trusted': 'Trusted: yes' in output,
            'name': 'Name not found',
            'device_class': '0x000000',
            'icon': 'mdi:bluetooth'
        }

        # Extraire le nom ET la classe en parcourant TOUTES les lignes (pas de break prématuré)
        for line in output.split('\n'):
            line = line.strip()
            if line.startswith('Name:'):
                details['name'] = line.split('Name:')[1].strip()
            elif line.startswith('Class:'):
                details['device_class'] = line.split('Class:')[1].strip()
                class_hex = details['device_class'].lower()
                if '0x2404' in class_hex:
                    details['icon'] = 'mdi:speaker'
                elif '0x5a020c' in class_hex:
                    details['icon'] = 'mdi:cellphone'
                elif '0x2508' in class_hex:
                    details['icon'] = 'mdi:watch'
            # Pas de 'break' ici. On continue à lire pour trouver Name et Class.

        return details
    except Exception as e:
        app.logger.error(f"Erreur get_device_details pour {mac_address}: {e}")
        return None
    
@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Scanner et lister les appareils Bluetooth avec leur état."""
    try:
        # 1. Lancer un scan rapide
        subprocess.run(['bluetoothctl', '--timeout=3', 'scan', 'on'], capture_output=True, timeout=5)
        time.sleep(1)  # Attendre la découverte

        # 2. Obtenir la liste brute des appareils connus
        list_result = subprocess.run(['bluetoothctl', 'devices'], capture_output=True, text=True)
        devices = []
        for line in list_result.stdout.split('\n'):
            if line.strip():
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    mac_address = parts[1]
                    # 3. Pour CHAQUE appareil, récupérer les infos détaillées
                    details = get_device_details(mac_address)
                    if details:
                        devices.append(details)

        # 4. Trier : les appareils connectés en premier
        devices.sort(key=lambda x: x['connected'], reverse=True)

        return jsonify({'success': True, 'devices': devices})

    except Exception as e:
        app.logger.error(f"Erreur lors du scan: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/connect', methods=['POST'])
def connect_device():
    """Connecter à un appareil Bluetooth (version finale robuste)"""
    try:
        data = request.get_json()
        address = data.get('address')
        app.logger.info(f"Tentative de connexion à l'appareil: {address}")

        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # 1. Tenter la connexion avec le timeout géré par Python, pas par la commande shell.
        connect_cmd = f"echo -e 'connect {address}\\n' | bluetoothctl"
        result = subprocess.run(connect_cmd, shell=True, capture_output=True, text=True, timeout=10)  # Timeout ici
        app.logger.info(f"Sortie de bluetoothctl: {result.stdout[:200]}...")

        time.sleep(3)

        # 2. VÉRIFICATION CRITIQUE : Obtenir l'état actuel de l'appareil
        info_cmd = f"echo 'info {address}' | bluetoothctl"
        info_result = subprocess.run(info_cmd, shell=True, capture_output=True, text=True, timeout=5)
        # Log seulement en cas d'échec pour ne pas surcharger
        if 'Connected: yes' not in info_result.stdout:
            app.logger.info(f"État de l'appareil: {info_result.stdout[:500]}")

        # 3. Détecter si l'appareil est connecté
        if 'Connected: yes' in info_result.stdout:
            app.logger.info(f"SUCCÈS : Appareil {address} est connecté.")
            return jsonify({'success': True, 'message': f'Appareil {address} connecté avec succès.'})
        else:
            error_msg = "Connexion échouée. Assurez-vous que l'appareil est allumé, appairé et à portée."
            if 'Device not available' in info_result.stdout:
                error_msg = "Appareil non disponible (hors de portée ou éteint)."
            app.logger.warning(f"ÉCHEC : {error_msg}")
            return jsonify({'success': False, 'error': error_msg}), 500

    except subprocess.TimeoutExpired:
        app.logger.error("Timeout lors de la commande bluetoothctl")
        return jsonify({'success': False, 'error': 'La commande a pris trop de temps.'}), 500
    except Exception as e:
        app.logger.error(f"Erreur inattendue: {str(e)}")
        return jsonify({'success': False, 'error': f'Erreur interne du serveur: {str(e)}'}), 500


@app.route('/api/disconnect', methods=['POST'])
def disconnect_device():
    """Déconnecter un appareil Bluetooth."""
    try:
        data = request.get_json()
        address = data.get('address')
        app.logger.info(f"Tentative de déconnexion de l'appareil: {address}")

        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # Commande de déconnexion
        disconnect_cmd = f"echo -e 'disconnect {address}\\n' | bluetoothctl"
        result = subprocess.run(disconnect_cmd, shell=True, capture_output=True, text=True, timeout=10)

        time.sleep(2)  # Attendre que l'état se mette à jour

        # Vérifier que l'appareil est bien déconnecté
        info_cmd = f"echo 'info {address}' | bluetoothctl"
        info_result = subprocess.run(info_cmd, shell=True, capture_output=True, text=True, timeout=5)

        if 'Connected: no' in info_result.stdout:
            app.logger.info(f"SUCCÈS : Appareil {address} est déconnecté.")
            return jsonify({'success': True, 'message': f'Appareil {address} déconnecté.'})
        else:
            app.logger.warning(f"ÉCHEC : Impossible de déconnecter {address}.")
            return jsonify({'success': False, 'error': 'Échec de la déconnexion.'}), 500

    except subprocess.TimeoutExpired:
        app.logger.error("Timeout lors de la déconnexion")
        return jsonify({'success': False, 'error': 'Timeout.'}), 500
    except Exception as e:
        app.logger.error(f"Erreur inattendue: {str(e)}")
        return jsonify({'success': False, 'error': f'Erreur interne: {str(e)}'}), 500
    
    
if __name__ == '__main__':
    # DÉMARRAGE DU SERVEUR - host='0.0.0.0' est essentiel
    app.run(host='0.0.0.0', port=3000, debug=False, threaded=True)