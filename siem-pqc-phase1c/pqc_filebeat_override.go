// Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
// or more contributor license agreements. Licensed under the Elastic License 2.0;
// you may not use this file except in compliance with the Elastic License 2.0.

package runtime

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/elastic/elastic-agent/pkg/component"
)

const (
	envPQCFilebeatBin        = "PQC_FILEBEAT_BIN"
	envLogstashTLSCurveTypes = "LOGSTASH_TLS_CURVE_TYPES"
	envLogstashTLSMinVersion = "LOGSTASH_TLS_MIN_VERSION"
	envLogstashTLSStrictPQC  = "LOGSTASH_TLS_STRICT_PQC"
	filebeatComponentBinary  = "filebeat"
)

type pqcFilebeatOverride struct {
	enabled      bool
	envSet       bool
	customPath   string
	originalPath string
	warning      string
}

type pqcLogstashEnvStatus struct {
	curveTypesPresent bool
	minVersionPresent bool
	strictPQCPresent  bool
}

func (s pqcLogstashEnvStatus) enabled() bool {
	return s.curveTypesPresent && s.minVersionPresent && s.strictPQCPresent
}

func resolvePQCFilebeatBinary(componentBinaryName string, originalPath string) pqcFilebeatOverride {
	overridePath, ok := os.LookupEnv(envPQCFilebeatBin)
	if !ok || strings.TrimSpace(overridePath) == "" {
		return pqcFilebeatOverride{originalPath: originalPath}
	}

	if !isFilebeatComponent(componentBinaryName) {
		return pqcFilebeatOverride{envSet: true, originalPath: originalPath}
	}

	absPath, err := filepath.Abs(overridePath)
	if err != nil {
		return pqcFilebeatOverride{
			envSet:       true,
			originalPath: originalPath,
			warning:      fmt.Sprintf("failed to resolve %s: %v", envPQCFilebeatBin, err),
		}
	}

	info, err := os.Stat(absPath)
	if err != nil {
		return pqcFilebeatOverride{
			envSet:       true,
			customPath:   absPath,
			originalPath: originalPath,
			warning:      fmt.Sprintf("%s points to an unavailable file %q: %v", envPQCFilebeatBin, absPath, err),
		}
	}
	if info.IsDir() {
		return pqcFilebeatOverride{
			envSet:       true,
			customPath:   absPath,
			originalPath: originalPath,
			warning:      fmt.Sprintf("%s points to a directory, expected file: %q", envPQCFilebeatBin, absPath),
		}
	}

	return pqcFilebeatOverride{
		enabled:      true,
		envSet:       true,
		customPath:   absPath,
		originalPath: originalPath,
	}
}

func isFilebeatComponent(componentBinaryName string) bool {
	name := strings.TrimSuffix(strings.ToLower(filepath.Base(componentBinaryName)), ".exe")
	return name == filebeatComponentBinary
}

func appendPQCLogstashEnv(env []string) ([]string, pqcLogstashEnvStatus) {
	var status pqcLogstashEnvStatus
	if value, ok := os.LookupEnv(envLogstashTLSCurveTypes); ok {
		env = append(env, fmt.Sprintf("%s=%s", envLogstashTLSCurveTypes, value))
		status.curveTypesPresent = true
	}
	if value, ok := os.LookupEnv(envLogstashTLSMinVersion); ok {
		env = append(env, fmt.Sprintf("%s=%s", envLogstashTLSMinVersion, value))
		status.minVersionPresent = true
	}
	if value, ok := os.LookupEnv(envLogstashTLSStrictPQC); ok {
		env = append(env, fmt.Sprintf("%s=%s", envLogstashTLSStrictPQC, value))
		status.strictPQCPresent = true
	}
	return env, status
}

func logstashHosts(comp component.Component) []string {
	if comp.OutputType != "logstash" {
		return nil
	}
	unit, ok := comp.OutputUnit()
	if !ok || unit.Config == nil || unit.Config.Source == nil {
		return nil
	}
	source := unit.Config.Source.AsMap()
	hosts, ok := source["hosts"]
	if !ok {
		return nil
	}
	switch v := hosts.(type) {
	case []string:
		return v
	case []interface{}:
		result := make([]string, 0, len(v))
		for _, h := range v {
			if s, ok := h.(string); ok {
				result = append(result, s)
			}
		}
		return result
	default:
		return nil
	}
}
