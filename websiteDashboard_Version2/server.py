from flask import Flask, send_from_directory
from flask_socketio import SocketIO
import re

app = Flask(__name__, static_folder="static")
socketio = SocketIO(app, cors_allowed_origins="*")

# Accept:
#  - "lat,lon"  e.g. "-37.8136,144.9631"
#  - Anything else -> chat
gps_re = re.compile(r"^\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*$")

@app.route("/")
def index():
    return send_from_directory("static", "index.html")

@app.route("/static/<path:path>")
def static_files(path):
    return send_from_directory("static", path)

@socketio.on("client_message")
def handle_client_message(data):
    text = str(data.get("text", "")).strip()

    m = gps_re.match(text)
    if m:
        lat = float(m.group(1))
        lon = float(m.group(3))
        socketio.emit("server_message", {"type": "gps", "lat": lat, "lon": lon})
    else:
        socketio.emit("server_message", {"type": "chat", "text": text})

if __name__ == "__main__":
    # Runs on your LAN so other laptop can connect
    socketio.run(app, host="0.0.0.0", port=8000)
