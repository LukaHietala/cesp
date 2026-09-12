## Protocol Spec

### Usage example

```py
import json
import socket
import struct

MAGIC_BYTE_1 = 0x0C
MAGIC_BYTE_2 = 0x0E
HEADER_SIZE = 6


def encode(obj):
    payload = json.dumps(obj).encode("utf-8")
    payload_len = len(payload)
    header = struct.pack(">BBI", MAGIC_BYTE_1, MAGIC_BYTE_2, payload_len)
    return header + payload


if __name__ == "__main__":
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect(("127.0.0.1", 8080))

        message = {"e": "auth:handshake", "p": {"name": "lentava_taskurotta"}}
        s.sendall(encode(message))

        header = s.recv(HEADER_SIZE)
        if len(header) < HEADER_SIZE:
            raise ValueError("Packet too short")

        # > - big endian, B - unsigned char, I - uint32
        m1, m2, payload_len = struct.unpack(">BBI", header)

        if m1 != MAGIC_BYTE_1 or m2 != MAGIC_BYTE_2:
            raise ValueError("Invalid magic bytes")


        payload = s.recv(payload_len))
        res = json.loads(payload.decode("utf-8"))
        print("Handshake res: ", res)

        s.close()
```
