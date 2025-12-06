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
    """Connecter à un appareil Bluetooth"""
    try:
        data = request.json
        address = data.get('address')
        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400
        
        # Commander la connexion via bluetoothctl
        cmd = f"echo -e 'connect {address}\n' | bluetoothctl"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        
        if 'Connection successful' in result.stdout:
            return jsonify({'success': True})
        else:
            return jsonify({'success': False, 'error': result.stderr}), 500
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

if __name__ == '__main__':
    # DÉMARRAGE DU SERVEUR - host='0.0.0.0' est essentiel
    app.run(host='0.0.0.0', port=3000, debug=False, threaded=True)