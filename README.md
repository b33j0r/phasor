# `phasor-lite`

An ECS and webgpu-based game library for zig latest.

## WebGPU over HTTPS (LAN / iPhone)

WebGPU requires a secure context, so use HTTPS when testing from another device on your LAN.

1) Install the mkcert root CA on your Mac (once):
```bash
mkcert -install
```
2) Install the mkcert root CA on the iPhone (AirDrop `rootCA.pem` from `mkcert -CAROOT` and trust it).
3) Run the wasm server with HTTPS (auto-generates `local/tls/phasor.pem` + `local/tls/phasor-key.pem` if missing):
```bash
zig build run-cube-wasm -- --host 0.0.0.0 --https --no-open
```
4) Open `https://b3.local:8443/` (or regenerate the cert with your LAN IP and use `https://<LAN-IP>:8443/`).

Notes:
- `0.0.0.0` is only for binding; browse to your LAN hostname/IP.
- HTTPS requires `python3` for the built-in TLS proxy.
- To include a LAN IP in the cert:
```bash
mkcert -cert-file local/tls/phasor.pem -key-file local/tls/phasor-key.pem b3.local <LAN-IP> 127.0.0.1 ::1 localhost
```
