package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type pvcCleaner struct {
	cfg *Config
}

type pvcResult struct {
	Removed  []string
	Found    bool
	Retained bool
}

func (p *pvcCleaner) run() (*pvcResult, error) {
	svc := p.cfg.ServiceName
	ns := p.cfg.Namespace

	pvcs, err := p.listPVCs()
	if err != nil {
		return nil, err
	}
	if len(pvcs) == 0 {
		fmt.Println("  → No PVCs found")
		return &pvcResult{Found: false}, nil
	}

	fmt.Printf("  → Found %d PVC(s) for %s:\n", len(pvcs), svc)
	for _, pvc := range pvcs {
		fmt.Printf("    • %s\n", pvc)
	}

	if !p.promptRetain() {
		fmt.Println("  → PVCs retained (operator chose to keep)")
		return &pvcResult{Found: true, Retained: true}, nil
	}

	var removed []string
	for _, pvc := range pvcs {
		fmt.Printf("  → Deleting PVC %s (ns=%s)\n", pvc, ns)
		cmd := exec.Command("kubectl", "delete", "pvc", pvc, "-n", ns, "--ignore-not-found")
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return nil, fmt.Errorf("%w: delete pvc %s: %s", ErrDeletionFailed, pvc, err)
		}
		removed = append(removed, pvc)
	}

	return &pvcResult{Removed: removed, Found: true}, nil
}

func (p *pvcCleaner) promptRetain() bool {
	if !isInteractive() {
		return true
	}

	fmt.Print("  → Delete PVCs? Type 'yes' to confirm, anything else to retain: ")
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(strings.ToLower(input))

	return input == "yes"
}

func isInteractive() bool {
	stat, _ := os.Stdin.Stat()
	return (stat.Mode() & os.ModeCharDevice) != 0
}

func (p *pvcCleaner) listPVCs() ([]string, error) {
	cmd := exec.Command("kubectl", "get", "pvc", "-n", p.cfg.Namespace,
		"-o", "jsonpath={.items[*].metadata.name}")
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("list PVCs: %w", err)
	}

	names := strings.Fields(string(out))
	var matched []string
	for _, name := range names {
		if strings.HasPrefix(name, p.cfg.ServiceName+"-") || name == p.cfg.ServiceName {
			matched = append(matched, name)
		}
	}
	return matched, nil
}
