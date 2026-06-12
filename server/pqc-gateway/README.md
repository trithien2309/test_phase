# PQC Gateway

This gateway terminates TLS 1.3 with `X25519MLKEM768` and forwards the raw Beats/Lumberjack stream to Logstash.

## Flow

```text
Windows Elastic Agent / Filebeat PQC
  -> TLS 1.3 + X25519MLKEM768
  -> siem-pqc-gateway :5443
  -> raw Beats/Lumberjack
  -> Logstash beats input :5044
  -> Elasticsearch index phase1-pqc-filebeat-*
```

## Install On Monitor Server

Prerequisites:

```text
Go 1.24 or newer
openssl
systemd
Logstash beats input reachable on 127.0.0.1:5044
```

Run from the repository root on the Ubuntu monitor:

```bash
cd server/pqc-gateway
chmod +x setup-pqc-gateway.sh check-pqc-gateway.sh
GATEWAY_IP=192.168.22.171 ./setup-pqc-gateway.sh
```

If Logstash reads pipeline files from a local directory, the setup script can copy the tested pipeline:

```bash
LOGSTASH_PIPELINE_DIR=/path/to/logstash/pipeline GATEWAY_IP=192.168.22.171 ./setup-pqc-gateway.sh
```

Restart Logstash after copying the pipeline.

## Check

```bash
./check-pqc-gateway.sh
```

Expected gateway logs:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```

The gateway does not decode events and does not modify the Lumberjack payload.
