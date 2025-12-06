from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import subprocess
import json
import os

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

@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Scanner et lister les appareils Bluetooth à proximité"""
    try:
        # Lancer un scan rapide
        subprocess.run(['bluetoothctl', '--timeout=5', 'scan', 'on'], capture_output=True, timeout=10)
        # Récupérer la liste des appareils découverts
        result = subprocess.run(['bluetoothctl', 'devices'], capture_output=True, text=True)
        devices = []
        for line in result.stdout.split('\n'):
            if line.strip():
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    devices.append({'address': parts[1], 'name': parts[2]})
        return jsonify({'success': True, 'devices': devices})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/connect', methods=['POST'])
def connect_device():
    """Connecter à un appareil Bluetooth (version robuste)"""
    import subprocess
    import time

    try:
        data = request.get_json()
        address = data.get('address')

        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # 1. Arrêter toute connexion existante (nettoyage)
        subprocess.run(['bluetoothctl', 'disconnect', address], capture_output=True, text=True)
        time.sleep(1)

        # 2. Vérifier/établir l'appairage (pair) et la confiance (trust)
        # Cela est nécessaire avant la connexion sur de nombreux systèmes
        trust_cmd = f"echo -e 'pair {address}\\ntrust {address}\\n' | bluetoothctl"
        trust_result = subprocess.run(trust_cmd, shell=True, capture_output=True, text=True, timeout=15)
        time.sleep(2)

        # 3. Tenter la connexion
        connect_cmd = f"echo -e 'connect {address}\\n' | bluetoothctl"
        connect_result = subprocess.run(connect_cmd, shell=True, capture_output=True, text=True, timeout=30)

        # 4. Analyser le résultat
        output = connect_result.stdout + connect_result.stderr
        if 'Connection successful' in output:
            return jsonify({'success': True, 'message': f'Connecté à {address}'})
        else:
            # Essayer de récupérer un message d'erreur plus précis
            error_lines = [line for line in output.split('\\n') if 'Failed' in line or 'Error' in line or 'not available' in line]
            error_msg = error_lines[0] if error_lines else 'Raison inconnue (voir les logs de l\'add-on)'
            return jsonify({'success': False, 'error': f'Échec de la connexion : {error_msg}'}), 500

    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'error': 'Timeout : la commande a pris trop de temps.'}), 500
    except Exception as e:
        # Cette exception capture toute autre erreur et la logge
        app.logger.error(f"Erreur inattendue dans connect_device: {str(e)}")
        return jsonify({'success': False, 'error': f'Erreur interne: {str(e)}'}), 500

if __name__ == '__main__':
    # DÉMARRAGE DU SERVEUR - host='0.0.0.0' est essentiel
    app.run(host='0.0.0.0', port=3000, debug=False, threaded=True)