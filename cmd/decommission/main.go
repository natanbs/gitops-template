package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
)

const version = "0.1.0"

func main() {
	cfg, listMode, listJSON := parseFlags()
	if cfg == nil {
		os.Exit(0)
	}

	if listMode {
		services, err := ListServices(cfg.Namespace)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(6)
		}
		if listJSON {
			if err := RenderJSON(os.Stdout, services); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(6)
			}
		} else {
			RenderTable(os.Stdout, services)
		}
		return
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		fmt.Fprintln(os.Stderr, "\nInterrupted: decommission may be incomplete. Check cluster state with: kubectl get all -n", cfg.Namespace)
		os.Exit(6)
	}()

	results, notes, err := run(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)

		switch {
		case isPreCheckError(err):
			os.Exit(1)
		case isNotFoundError(err):
			os.Exit(2)
		case isDeletionError(err):
			os.Exit(3)
		case isRegistryError(err):
			os.Exit(4)
		default:
			os.Exit(5)
		}
	}

	signal.Stop(sigCh)

	fmt.Printf("\n✓ Decommission of %s complete\n", cfg.ServiceName)

	notesStr := ""
	if len(notes) > 0 {
		notesStr = strings.Join(notes, "; ")
	}

	auditRec := AuditRecord{
		ServiceName:      cfg.ServiceName,
		Namespace:        cfg.Namespace,
		DeploymentModel:  results.Model,
		Operator:         cfg.Operator,
		PreChecksPassed:  results.PreChecksOK,
		ResourcesRemoved: results.Removed,
		ImageDeleted:     results.ImageDeleted,
		Status:           "success",
		Notes:            notesStr,
	}

	if err := writeAudit(auditRec, cfg); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: audit write failed: %v\n", err)
	}
}

type runResult struct {
	Model        string
	PreChecksOK  bool
	Removed      []string
	ImageDeleted bool
	ImageRef     string
}

func run(cfg *Config) (*runResult, []string, error) {
	if cfg.DryRun {
		res, err := dryRun(cfg)
		return res, nil, err
	}

	var notes []string

	if !cfg.Force {
		checks, err := runPreChecks(cfg)
		if err != nil {
			return nil, notes, fmt.Errorf("pre-checks failed: %w", err)
		}
		_ = checks
	}

	model, err := detectModel(cfg.ServiceName)
	if err != nil {
		return nil, notes, fmt.Errorf("detect deployment model: %w", err)
	}

	result := &runResult{
		Model:       model.String(),
		PreChecksOK: !cfg.Force,
	}

	switch model {
	case ModelGitOps:
		g := &gitopsDecommissioner{cfg: cfg}
		removed, err := g.run()
		if err != nil {
			return nil, notes, fmt.Errorf("gitops decommission: %w", err)
		}
		result.Removed = removed
	case ModelDirect:
		d := &directDecommissioner{cfg: cfg}
		removed, imageRef, err := d.run()
		if err != nil {
			return nil, notes, fmt.Errorf("direct decommission: %w", err)
		}
		result.Removed = removed
		result.ImageRef = imageRef
	}

	pc := &pvcCleaner{cfg: cfg}
	pvcRes, err := pc.run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "  Warning: PVC cleanup: %v\n", err)
		notes = append(notes, fmt.Sprintf("PVC error: %v", err))
	} else {
		result.Removed = append(result.Removed, pvcRes.Removed...)
		if pvcRes.Retained {
			notes = append(notes, "Operator chose to retain PVCs")
		}
	}

	if result.ImageRef != "" {
		fmt.Println("  → Cleaning up container image from registry")
		if err := deleteImage(result.ImageRef, cfg); err != nil {
			fmt.Fprintf(os.Stderr, "  Warning: image cleanup: %v\n", err)
		} else {
			result.ImageDeleted = true
		}
	}

	return result, notes, nil
}

func parseFlags() (cfg *Config, listMode bool, listJSON bool) {
	var (
		namespace = flag.String("namespace", "", "K8s namespace (default: all-namespaces for --list, \"default\" for decommission)")
		flagForce = flag.Bool("force", false, "Skip pre-decommission safety checks")
		dryRun    = flag.Bool("dry-run", false, "Show planned actions without executing")
		jsonOut   = flag.Bool("json", false, "Output audit record as JSON")
		auditDir  = flag.String("audit-dir", "./decommission-audit/", "Directory for audit log files")
		operator  = flag.String("operator", os.Getenv("USER"), "Operator name for audit trail")
		showVer   = flag.Bool("version", false, "Print version and exit")
		showHelp  = flag.Bool("help", false, "Print help text and exit")
		flagList  = flag.Bool("list", false, "List all available services")
	)

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: decommission <service-name> [flags]\n\nFlags:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExit codes:\n  0  Success\n  1  Pre-checks failed\n  2  Deployment not found\n  3  Deletion failed\n  4  Registry cleanup failed (non-fatal)\n  5  Invalid arguments\n  6  Cluster unreachable\n")
	}
	flag.Parse()

	if *showHelp {
		flag.Usage()
		return nil, false, false
	}
	if *showVer {
		fmt.Printf("decommission version %s\n", version)
		return nil, false, false
	}

	if *flagList {
		if flag.NArg() > 0 {
			fmt.Fprintln(os.Stderr, "Error: --list cannot be used with a service name")
			os.Exit(5)
		}
		return &Config{
			Namespace: *namespace,
		}, true, *jsonOut
	}

	if flag.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "Error: service-name is required")
		fmt.Fprintf(os.Stderr, "Usage: decommission <service-name> [flags]\n")
		os.Exit(5)
	}

	ns := *namespace
	if ns == "" {
		ns = "default"
	}
	return &Config{
		ServiceName: flag.Arg(0),
		Namespace:   ns,
		Force:       *flagForce,
		DryRun:      *dryRun,
		JSON:        *jsonOut,
		AuditDir:    *auditDir,
		Operator:    *operator,
	}, false, false
}

func isPreCheckError(err error) bool {
	return errors.Is(err, ErrNoKubectl) || errors.Is(err, ErrNoArgoCD) ||
		errors.Is(err, ErrNoGit) || errors.Is(err, ErrPreCheckFailed) ||
		errors.Is(err, ErrActiveTraffic) || errors.Is(err, ErrUncommittedChange) ||
		errors.Is(err, ErrServiceNotFound)
}

func isNotFoundError(err error) bool {
	return errors.Is(err, ErrServiceNotFound)
}

func isDeletionError(err error) bool {
	return errors.Is(err, ErrDeletionFailed)
}

func isRegistryError(err error) bool {
	return errors.Is(err, ErrRegistryCleanup)
}
