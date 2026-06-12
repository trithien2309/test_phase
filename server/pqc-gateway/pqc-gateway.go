package main

import (
	"bufio"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type config struct {
	ListenAddr string
	ForwardTo  string
	CertFile   string
	KeyFile    string
}

type countingWriter struct {
	w io.Writer
	n int64
}

func (c *countingWriter) Write(p []byte) (int, error) {
	n, err := c.w.Write(p)
	c.n += int64(n)
	return n, err
}

func main() {
	configPath := flag.String("config", "gateway.yaml", "path to gateway config")
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil {
		log.Fatalf("failed loading config: %v", err)
	}

	cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
	if err != nil {
		log.Fatalf("failed loading TLS certificate: %v", err)
	}

	tlsCfg := &tls.Config{
		MinVersion:       tls.VersionTLS13,
		MaxVersion:       tls.VersionTLS13,
		Certificates:     []tls.Certificate{cert},
		CurvePreferences: []tls.CurveID{tls.X25519MLKEM768},
	}

	ln, err := net.Listen("tcp", cfg.ListenAddr)
	if err != nil {
		log.Fatalf("failed listening on %s: %v", cfg.ListenAddr, err)
	}
	defer ln.Close()

	log.Printf("NCS PQC gateway listening on %s and forwarding raw Beats/Lumberjack to %s", cfg.ListenAddr, cfg.ForwardTo)
	log.Printf("TLS policy: min=TLS1.3 max=TLS1.3 curve_preferences=[X25519MLKEM768]")

	var connID uint64
	for {
		rawConn, err := ln.Accept()
		if err != nil {
			log.Printf("accept error: %v", err)
			continue
		}
		id := atomic.AddUint64(&connID, 1)
		go handle(id, rawConn, tlsCfg, cfg.ForwardTo)
	}
}

func loadConfig(path string) (config, error) {
	cfg := config{
		ListenAddr: "0.0.0.0:5443",
		ForwardTo:  "127.0.0.1:5044",
		CertFile:   "/etc/siem-pqc-gateway/certs/server.crt",
		KeyFile:    "/etc/siem-pqc-gateway/certs/server.key",
	}

	f, err := os.Open(path)
	if err != nil {
		return cfg, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "-") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.Trim(strings.TrimSpace(parts[1]), `"'`)
		switch key {
		case "listen":
			cfg.ListenAddr = value
		case "forward_to":
			cfg.ForwardTo = value
		case "cert_file":
			cfg.CertFile = value
		case "key_file":
			cfg.KeyFile = value
		}
	}
	if err := scanner.Err(); err != nil {
		return cfg, err
	}

	if cfg.ListenAddr == "" || cfg.ForwardTo == "" || cfg.CertFile == "" || cfg.KeyFile == "" {
		return cfg, fmt.Errorf("listen, forward_to, cert_file, and key_file are required")
	}
	return cfg, nil
}

func handle(id uint64, rawClient net.Conn, tlsCfg *tls.Config, forwardTo string) {
	defer rawClient.Close()
	client := tls.Server(rawClient, tlsCfg)
	_ = client.SetDeadline(time.Now().Add(15 * time.Second))
	if err := client.Handshake(); err != nil {
		log.Printf("[conn=%d] handshake failed remote=%s error=%v", id, rawClient.RemoteAddr(), err)
		return
	}
	_ = client.SetDeadline(time.Time{})

	state := client.ConnectionState()
	log.Printf("[conn=%d] handshake ok remote=%s tls_version=%s cipher=%s server_name=%q configured_curve_preferences=[X25519MLKEM768] selected_group_proof_required_from_gateway_or_pcap=true",
		id, rawClient.RemoteAddr(), tlsVersionName(state.Version), tls.CipherSuiteName(state.CipherSuite), state.ServerName)

	backend, err := net.DialTimeout("tcp", forwardTo, 10*time.Second)
	if err != nil {
		log.Printf("[conn=%d] failed connecting backend=%s error=%v", id, forwardTo, err)
		return
	}
	defer backend.Close()

	log.Printf("[conn=%d] forwarding raw Beats/Lumberjack stream to %s", id, forwardTo)

	clientToBackend := &countingWriter{w: backend}
	backendToClient := &countingWriter{w: client}

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, _ = io.Copy(clientToBackend, client)
		if tcp, ok := backend.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		}
	}()
	go func() {
		defer wg.Done()
		_, _ = io.Copy(backendToClient, backend)
		if tcp, ok := rawClient.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		}
	}()
	wg.Wait()

	log.Printf("[conn=%d] connection closed: client->logstash bytes=%d | logstash->client bytes=%d",
		id, clientToBackend.n, backendToClient.n)
}

func tlsVersionName(v uint16) string {
	switch v {
	case tls.VersionTLS13:
		return "TLS 1.3"
	case tls.VersionTLS12:
		return "TLS 1.2"
	default:
		return fmt.Sprintf("0x%04x", v)
	}
}
