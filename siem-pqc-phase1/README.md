# SIEM PQC Phase 1

This folder contains the public test handoff for Phase 1 of the custom Elastic Agent or Beats PQC client work.

## Artifacts

- `elastic-agent-pqc-windows-amd64.zip`
- `filebeat-pqc-windows-amd64.zip`
- `filebeat-pqc-linux-amd64.zip`

## Docs

- `PHASE1_PQC_AGENT_NOTES.md`
- `PHASE1_PQC_AGENT_BUILD.md`
- `PHASE1_PQC_AGENT_TEST.md`

## Quick test

1. Extract the artifact you need.
2. Use the scripts in `tools/pqc-test`.
3. Point Logstash output to `192.168.22.171:5443`.
4. Use gateway logs or packet capture to prove negotiated group `X25519MLKEM768`.
