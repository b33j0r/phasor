#!/usr/bin/env python3
import argparse
import socket
import ssl
import threading


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except Exception:
            pass


def handle_connection(conn, target_host, target_port):
    try:
        upstream = socket.create_connection((target_host, target_port))
    except Exception:
        conn.close()
        return
    t1 = threading.Thread(target=pump, args=(conn, upstream), daemon=True)
    t2 = threading.Thread(target=pump, args=(upstream, conn), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    conn.close()
    upstream.close()


def main():
    parser = argparse.ArgumentParser(description="TLS proxy for the wasm server")
    parser.add_argument("--listen-host", required=True)
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", type=int, required=True)
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    args = parser.parse_args()

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=args.cert, keyfile=args.key)

    family = socket.AF_INET6 if ":" in args.listen_host else socket.AF_INET
    server = socket.socket(family, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen_host, args.listen_port))
    server.listen(128)

    while True:
        conn, _addr = server.accept()
        try:
            tls_conn = context.wrap_socket(conn, server_side=True)
        except ssl.SSLError:
            conn.close()
            continue
        threading.Thread(
            target=handle_connection,
            args=(tls_conn, args.target_host, args.target_port),
            daemon=True,
        ).start()


if __name__ == "__main__":
    main()
