package main

import "fmt"

type DeploymentModel int

const (
	ModelUnknown DeploymentModel = iota
	ModelGitOps
	ModelDirect
)

func (m DeploymentModel) String() string {
	switch m {
	case ModelGitOps:
		return "gitops"
	case ModelDirect:
		return "direct"
	default:
		return "unknown"
	}
}

type ServiceInfo struct {
	Name              string `json:"name"`
	Namespace         string `json:"namespace"`
	DeploymentModel   string `json:"deployment_model"`
	Status            string `json:"status"`
	AvailableReplicas int    `json:"available_replicas"`
	DesiredReplicas   int    `json:"desired_replicas,omitempty"`
}

type ServiceList struct {
	Services   []ServiceInfo `json:"services"`
	TotalCount int           `json:"total_count"`
}

type AuditRecord struct {
	ServiceName      string   `json:"service_name"`
	Namespace        string   `json:"namespace"`
	DeploymentModel  string   `json:"deployment_model"`
	Operator         string   `json:"operator"`
	Timestamp        string   `json:"timestamp"`
	PreChecksPassed  bool     `json:"pre_checks_passed"`
	ResourcesRemoved []string `json:"resources_removed"`
	ImageDeleted     bool     `json:"image_deleted"`
	Status           string   `json:"status"`
	Notes            string   `json:"notes,omitempty"`
}

type Config struct {
	ServiceName string
	Namespace   string
	Force       bool
	DryRun      bool
	JSON        bool
	AuditDir    string
	Operator    string
	ImageRef    string
}

type stepResult struct {
	Step    string
	Success bool
	Message string
}

var (
	ErrServiceNotFound   = fmt.Errorf("service not found in namespace")
	ErrNoKubectl         = fmt.Errorf("kubectl not found on PATH")
	ErrNoArgoCD          = fmt.Errorf("argocd CLI not found on PATH")
	ErrNoGit             = fmt.Errorf("git not found on PATH")
	ErrPreCheckFailed    = fmt.Errorf("pre-check failed")
	ErrDeletionFailed    = fmt.Errorf("resource deletion failed")
	ErrRegistryCleanup   = fmt.Errorf("registry cleanup failed")
	ErrInvalidArgs       = fmt.Errorf("invalid arguments")
	ErrActiveTraffic     = fmt.Errorf("service has active connections")
	ErrUncommittedChange = fmt.Errorf("app repo has uncommitted changes")
)
