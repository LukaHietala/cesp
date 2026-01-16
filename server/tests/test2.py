import socket
import time

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8080))

    # Fill buffer almost full
    print("Test large message...")
    large_msg = b"A" * 1000 + b"\n"
    s.sendall(large_msg)
    input()

    # Send message which will be split
    print("Test message...")
    s.sendall(b"Moro kaikki se on Lakko taalla ja tanaan me tullaan pelaamaan vahan Roblox peleja\n")
    input()

    s.close()

if __name__ == "__main__":
    main()
