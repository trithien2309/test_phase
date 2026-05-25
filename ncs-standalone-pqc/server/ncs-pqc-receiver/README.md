# NCS PQC Receiver

This receiver terminates TLS 1.3 with `X25519MLKEM768` and forwards the raw Beats/Lumberjack stream to a normal Logstash beats input.

## Flow

```text
Elastic Agent / Filebeat PQC
  -> TLS 1.3 + X25519MLKEM768
  -> siem-pqc-gateway :5443
  -> raw Beats/Lumberjack
  -> Logstash beats input 127.0.0.1:5044
  -> Elasticsearch index ncs-windows-pqc-*
```

For Docker Logstash, the beats input binds `0.0.0.0` inside the container. Restrict exposure at Docker publish/firewall level so external clients use only the PQC Gateway.

## Install

```bash
cd server/ncs-pqc-receiver
chmod +x setup-ncs-pqc-receiver.sh check-ncs-pqc-receiver.sh
./setup-ncs-pqc-receiver.sh
```

If you want the setup script to copy the Logstash pipeline too:

```bash
LOGSTASH_PIPELINE_DIR=/path/to/logstash/pipeline ./setup-ncs-pqc-receiver.sh
```

Then restart Logstash.

## Check

```bash
./check-ncs-pqc-receiver.sh
```

Expected gateway logs:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```

The gateway does not decode events and does not modify the Lumberjack payload.
