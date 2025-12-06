from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

@app.route('/api/status', methods=['GET'])
def get_status():
    """Endpoint de test pour vérifier que le serveur fonctionne."""
    return jsonify({'status': 'ok', 'service': 'Bluetooth Audio Gateway'})

@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Endpoint pour lister les appareils (version simulée pour le test)."""
    # Pour l'instant, retourne une liste vide
    return jsonify({'success': True, 'devices': []})

if __name__ == '__main__':
    # IL EST CRITIQUE d'utiliser host='0.0.0.0'
    app.run(host='0.0.0.0', port=3000, debug=False)