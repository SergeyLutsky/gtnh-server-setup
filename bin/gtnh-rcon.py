#!/usr/bin/env python3
"""Minimal Minecraft RCON client; Python standard library only."""
import socket, struct, sys

def packet(request_id, kind, payload):
    body = struct.pack("<ii", request_id, kind) + payload.encode() + b"\0\0"
    return struct.pack("<i", len(body)) + body

def receive(sock):
    size_raw = sock.recv(4)
    if len(size_raw) != 4:
        raise RuntimeError("short RCON response")
    size = struct.unpack("<i", size_raw)[0]
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("closed RCON connection")
        data += chunk
    request_id, kind = struct.unpack("<ii", data[:8])
    return request_id, kind, data[8:-2].decode(errors="replace")

def main():
    if len(sys.argv) < 4:
        raise SystemExit("usage: gtnh-rcon.py PORT PASSWORD COMMAND")
    port, password, command = int(sys.argv[1]), sys.argv[2], " ".join(sys.argv[3:])
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=30) as sock:
            sock.sendall(packet(1, 3, password))
            request_id, _, _ = receive(sock)
            if request_id == -1:
                raise SystemExit("RCON authentication failed")
            sock.sendall(packet(2, 2, command))
            _, _, message = receive(sock)
            print(message)
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"RCON unavailable: {error}") from None

if __name__ == "__main__":
    main()
