package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestRenderTable_Empty(t *testing.T) {
	list := &ServiceList{Services: []ServiceInfo{}, TotalCount: 0}
	var buf bytes.Buffer
	RenderTable(&buf, list)
	out := buf.String()
	if !strings.Contains(out, "NAMESPACE") {
		t.Errorf("expected table headers, got: %s", out)
	}
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 1 {
		t.Errorf("expected 1 line (headers only), got %d", len(lines))
	}
}

func TestRenderTable_SingleEntry(t *testing.T) {
	list := &ServiceList{
		Services: []ServiceInfo{
			{Name: "my-api", Namespace: "default", DeploymentModel: "direct", Status: "Ready", AvailableReplicas: 3, DesiredReplicas: 3},
		},
		TotalCount: 1,
	}
	var buf bytes.Buffer
	RenderTable(&buf, list)
	out := buf.String()
	if !strings.Contains(out, "my-api") {
		t.Errorf("expected service name in output, got: %s", out)
	}
	if !strings.Contains(out, "direct") {
		t.Errorf("expected deployment model in output, got: %s", out)
	}
	if !strings.Contains(out, "3/3") {
		t.Errorf("expected 3/3 replicas, got: %s", out)
	}
}

func TestRenderTable_MultipleSorted(t *testing.T) {
	list := &ServiceList{
		Services: []ServiceInfo{
			{Name: "a-service", Namespace: "default", DeploymentModel: "direct", Status: "Ready", AvailableReplicas: 2, DesiredReplicas: 2},
			{Name: "b-service", Namespace: "prod", DeploymentModel: "gitops", Status: "Ready", AvailableReplicas: 5, DesiredReplicas: 5},
		},
		TotalCount: 2,
	}
	var buf bytes.Buffer
	RenderTable(&buf, list)
	out := buf.String()
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines (header + 2 services), got %d", len(lines))
	}
	if !strings.HasPrefix(lines[1], "default") {
		t.Errorf("expected first service line to start with 'default', got: %s", lines[1])
	}
	if !strings.HasPrefix(lines[2], "prod") {
		t.Errorf("expected second service line to start with 'prod', got: %s", lines[2])
	}
}

func TestRenderTable_NotReady(t *testing.T) {
	list := &ServiceList{
		Services: []ServiceInfo{
			{Name: "cache-redis", Namespace: "staging", DeploymentModel: "direct", Status: "Not Ready", AvailableReplicas: 0, DesiredReplicas: 1},
		},
		TotalCount: 1,
	}
	var buf bytes.Buffer
	RenderTable(&buf, list)
	out := buf.String()
	if !strings.Contains(out, "Not Ready") {
		t.Errorf("expected Not Ready status in output, got: %s", out)
	}
}

func TestRenderTable_Unknown(t *testing.T) {
	list := &ServiceList{
		Services: []ServiceInfo{
			{Name: "unknown-svc", Namespace: "default", DeploymentModel: "direct", Status: "Unknown", AvailableReplicas: 0, DesiredReplicas: 0},
		},
		TotalCount: 1,
	}
	var buf bytes.Buffer
	RenderTable(&buf, list)
	out := buf.String()
	if !strings.Contains(out, "0/0") {
		t.Errorf("expected 0/0 replicas for Unknown status, got: %s", out)
	}
}

func TestRenderJSON_Empty(t *testing.T) {
	list := &ServiceList{Services: []ServiceInfo{}, TotalCount: 0}
	var buf bytes.Buffer
	if err := RenderJSON(&buf, list); err != nil {
		t.Fatalf("RenderJSON error: %v", err)
	}
	var decoded ServiceList
	if err := json.Unmarshal(buf.Bytes(), &decoded); err != nil {
		t.Fatalf("invalid JSON output: %v", err)
	}
	if len(decoded.Services) != 0 {
		t.Errorf("expected 0 services, got %d", len(decoded.Services))
	}
	if decoded.TotalCount != 0 {
		t.Errorf("expected total_count 0, got %d", decoded.TotalCount)
	}
}

func TestRenderJSON_Populated(t *testing.T) {
	list := &ServiceList{
		Services: []ServiceInfo{
			{Name: "my-api", Namespace: "default", DeploymentModel: "direct", Status: "Ready", AvailableReplicas: 3, DesiredReplicas: 3},
			{Name: "web-frontend", Namespace: "production", DeploymentModel: "gitops", Status: "Ready", AvailableReplicas: 5, DesiredReplicas: 5},
		},
		TotalCount: 2,
	}
	var buf bytes.Buffer
	if err := RenderJSON(&buf, list); err != nil {
		t.Fatalf("RenderJSON error: %v", err)
	}
	var decoded ServiceList
	if err := json.Unmarshal(buf.Bytes(), &decoded); err != nil {
		t.Fatalf("invalid JSON output: %v", err)
	}
	if len(decoded.Services) != 2 {
		t.Errorf("expected 2 services, got %d", len(decoded.Services))
	}
	if decoded.Services[0].Name != "my-api" {
		t.Errorf("expected first service 'my-api', got '%s'", decoded.Services[0].Name)
	}
	if decoded.Services[0].DeploymentModel != "direct" {
		t.Errorf("expected deployment model 'direct', got '%s'", decoded.Services[0].DeploymentModel)
	}
}

func TestJSONTags(t *testing.T) {
	list := &ServiceList{
		Services: []ServiceInfo{
			{Name: "test", Namespace: "ns", DeploymentModel: "gitops", Status: "Ready", AvailableReplicas: 1, DesiredReplicas: 1},
		},
		TotalCount: 1,
	}
	var buf bytes.Buffer
	RenderJSON(&buf, list)
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(buf.Bytes(), &raw); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if _, ok := raw["services"]; !ok {
		t.Error("expected 'services' key in JSON output")
	}
	if _, ok := raw["total_count"]; !ok {
		t.Error("expected 'total_count' key in JSON output")
	}
}
