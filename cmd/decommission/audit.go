package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func writeAudit(rec AuditRecord, cfg *Config) error {
	timestamp := time.Now().UTC().Format(time.RFC3339)
	rec.Timestamp = timestamp

	if cfg.JSON {
		return writeAuditJSON(rec, cfg)
	}
	return writeAuditText(rec, cfg)
}

func writeAuditText(rec AuditRecord, cfg *Config) error {
	output := fmt.Sprintf(`Service: %s
Namespace: %s
Deployment Model: %s
Decommissioned By: %s
Date: %s
Pre-checks Passed: %v
Resources Removed: %v
Container Image Deleted: %v
Status: %s
Notes: %s
`,
		rec.ServiceName,
		rec.Namespace,
		rec.DeploymentModel,
		rec.Operator,
		rec.Timestamp,
		rec.PreChecksPassed,
		rec.ResourcesRemoved,
		rec.ImageDeleted,
		rec.Status,
		rec.Notes,
	)

	fmt.Println(output)

	if err := os.MkdirAll(cfg.AuditDir, 0755); err != nil {
		return fmt.Errorf("create audit dir: %w", err)
	}

	filename := fmt.Sprintf("%s-%s.txt", time.Now().UTC().Format("2006-01-02"), rec.ServiceName)
	path := filepath.Join(cfg.AuditDir, filename)
	return os.WriteFile(path, []byte(output), 0644)
}

func writeAuditJSON(rec AuditRecord, cfg *Config) error {
	data, err := json.MarshalIndent(rec, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal audit: %w", err)
	}

	fmt.Println(string(data))

	if err := os.MkdirAll(cfg.AuditDir, 0755); err != nil {
		return fmt.Errorf("create audit dir: %w", err)
	}

	filename := fmt.Sprintf("%s-%s.json", time.Now().UTC().Format("2006-01-02"), rec.ServiceName)
	path := filepath.Join(cfg.AuditDir, filename)
	return os.WriteFile(path, data, 0644)
}
