// Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
// or more contributor license agreements. Licensed under the Elastic License 2.0;
// you may not use this file except in compliance with the Elastic License 2.0.

package runtime

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/structpb"

	"github.com/elastic/elastic-agent-client/v7/pkg/client"
	"github.com/elastic/elastic-agent-client/v7/pkg/proto"
	"github.com/elastic/elastic-agent/pkg/component"
)

func TestResolvePQCFilebeatBinaryDisabledWhenEnvUnset(t *testing.T) {
	override := resolvePQCFilebeatBinary("filebeat", "/original/filebeat")
	require.False(t, override.enabled)
	require.Equal(t, "/original/filebeat", override.originalPath)
}

func TestResolvePQCFilebeatBinaryIgnoresNonFilebeatComponent(t *testing.T) {
	custom := writeExecutablePlaceholder(t)
	t.Setenv(envPQCFilebeatBin, custom)

	override := resolvePQCFilebeatBinary("metricbeat", "/original/metricbeat")
	require.False(t, override.enabled)
	require.True(t, override.envSet)
	require.Equal(t, "/original/metricbeat", override.originalPath)
}

func TestResolvePQCFilebeatBinaryEnablesForFilebeat(t *testing.T) {
	custom := writeExecutablePlaceholder(t)
	t.Setenv(envPQCFilebeatBin, custom)

	override := resolvePQCFilebeatBinary("filebeat", "/original/filebeat")
	require.True(t, override.enabled)
	require.True(t, override.envSet)
	require.Equal(t, "/original/filebeat", override.originalPath)
	require.Equal(t, mustAbs(t, custom), override.customPath)
}

func TestResolvePQCFilebeatBinaryAcceptsWindowsExeName(t *testing.T) {
	custom := writeExecutablePlaceholder(t)
	t.Setenv(envPQCFilebeatBin, custom)

	override := resolvePQCFilebeatBinary("filebeat.exe", "/original/filebeat.exe")
	require.True(t, override.enabled)
	require.Equal(t, mustAbs(t, custom), override.customPath)
}

func TestResolvePQCFilebeatBinaryFallsBackOnMissingPath(t *testing.T) {
	t.Setenv(envPQCFilebeatBin, filepath.Join(t.TempDir(), "missing-filebeat"))

	override := resolvePQCFilebeatBinary("filebeat", "/original/filebeat")
	require.False(t, override.enabled)
	require.True(t, override.envSet)
	require.Equal(t, "/original/filebeat", override.originalPath)
	require.Contains(t, override.warning, envPQCFilebeatBin)
}

func TestResolvePQCFilebeatBinaryFallsBackOnDirectory(t *testing.T) {
	dir := t.TempDir()
	t.Setenv(envPQCFilebeatBin, dir)

	override := resolvePQCFilebeatBinary("filebeat", "/original/filebeat")
	require.False(t, override.enabled)
	require.True(t, override.envSet)
	require.Equal(t, "/original/filebeat", override.originalPath)
	require.Contains(t, override.warning, "expected file")
}

func TestAppendPQCLogstashEnv(t *testing.T) {
	t.Setenv(envLogstashTLSCurveTypes, "X25519MLKEM768")
	t.Setenv(envLogstashTLSMinVersion, "1.3")
	t.Setenv(envLogstashTLSStrictPQC, "true")

	env, status := appendPQCLogstashEnv([]string{"EXISTING=value"})
	require.Contains(t, env, "EXISTING=value")
	require.Contains(t, env, envLogstashTLSCurveTypes+"=X25519MLKEM768")
	require.Contains(t, env, envLogstashTLSMinVersion+"=1.3")
	require.Contains(t, env, envLogstashTLSStrictPQC+"=true")
	require.True(t, status.enabled())
}

func TestAppendPQCLogstashEnvPartial(t *testing.T) {
	t.Setenv(envLogstashTLSCurveTypes, "X25519MLKEM768")

	env, status := appendPQCLogstashEnv(nil)
	require.Contains(t, env, envLogstashTLSCurveTypes+"=X25519MLKEM768")
	require.True(t, status.curveTypesPresent)
	require.False(t, status.minVersionPresent)
	require.False(t, status.strictPQCPresent)
	require.False(t, status.enabled())
}

func TestLogstashHosts(t *testing.T) {
	source, err := structpb.NewStruct(map[string]interface{}{
		"hosts": []interface{}{"192.168.22.171:5443"},
	})
	require.NoError(t, err)

	hosts := logstashHosts(component.Component{
		OutputType: "logstash",
		Units: []component.Unit{
			{
				Type: client.UnitTypeOutput,
				Config: &proto.UnitExpectedConfig{
					Source: source,
				},
			},
		},
	})

	require.Equal(t, []string{"192.168.22.171:5443"}, hosts)
}

func TestLogstashHostsIgnoresNonLogstashOutput(t *testing.T) {
	hosts := logstashHosts(component.Component{OutputType: "elasticsearch"})
	require.Nil(t, hosts)
}

func writeExecutablePlaceholder(t *testing.T) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "filebeat-pqc")
	require.NoError(t, os.WriteFile(path, []byte("placeholder"), 0o700))
	return path
}

func mustAbs(t *testing.T, path string) string {
	t.Helper()

	abs, err := filepath.Abs(path)
	require.NoError(t, err)
	return abs
}
