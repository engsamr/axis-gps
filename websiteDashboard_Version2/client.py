import socketio

SERVER = "http://LAPTOP_A_IP:8000"  # <-- change to Laptop A IP

sio = socketio.Client()

@sio.event
def connect():
    print("Connected to server.")

@sio.event
def disconnect():
    print("Disconnected.")

def main():
    sio.connect(SERVER)

    print("Type:")
    print("  lat,lon   e.g. -37.8136,144.9631")
    print("  or any chat message")
    print("Ctrl+C to quit.\n")

    try:
        while True:
            text = input("> ").strip()
            if not text:
                continue
            sio.emit("client_message", {"text": text})
    except KeyboardInterrupt:
        pass
    finally:
        sio.disconnect()

if _name_ == "_main_":
    main()