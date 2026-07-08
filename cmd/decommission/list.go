package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"sort"
	"text/tabwriter"
)

type deploymentList struct {
	Items []deploymentItem `json:"items"`
}

type deploymentItem struct {
	Metadata struct {
		Name      string `json:"name"`
		Namespace string `json:"namespace"`
	} `json:"metadata"`
	Status struct {
		Replicas          int `json:"replicas"`
		AvailableReplicas int `json:"availableReplicas"`
	} `json:"status"`
}

type applicationList struct {
	Items []applicationItem `json:"items"`
}

type applicationItem struct {
	Metadata struct {
		Name string `json:"name"`
	} `json:"metadata"`
}

func ListServices(namespace string) (*ServiceList, error) {
	deployArgs := []string{"get", "deployments"}
	if namespace != "" {
		deployArgs = append(deployArgs, "-n", namespace)
	} else {
		deployArgs = append(deployArgs, "--all-namespaces")
	}
	deployArgs = append(deployArgs, "-o", "json")

	deployCmd := exec.Command("kubectl", deployArgs...)
	deployOut, err := deployCmd.Output()
	if err != nil {
		return nil, fmt.Errorf("cannot reach cluster: %w", err)
	}

	var dl deploymentList
	if err := json.Unmarshal(deployOut, &dl); err != nil {
		return nil, fmt.Errorf("parse deployments: %w", err)
	}

	appCmd := exec.Command("kubectl", "get", "applications", "-n", "argocd", "-o", "json")
	appOut, appErr := appCmd.Output()

	gitOpsNames := make(map[string]bool)
	if appErr == nil {
		var al applicationList
		if err := json.Unmarshal(appOut, &al); err == nil {
			for _, item := range al.Items {
				gitOpsNames[item.Metadata.Name] = true
			}
		}
	}

	services := make([]ServiceInfo, 0, len(dl.Items))
	for _, d := range dl.Items {
		model := "direct"
		if gitOpsNames[d.Metadata.Name] {
			model = "gitops"
		}

		status := "Unknown"
		if d.Status.Replicas > 0 {
			if d.Status.AvailableReplicas >= d.Status.Replicas {
				status = "Ready"
			} else {
				status = "Not Ready"
			}
		} else if d.Status.AvailableReplicas > 0 {
			status = "Ready"
		}

		services = append(services, ServiceInfo{
			Name:              d.Metadata.Name,
			Namespace:         d.Metadata.Namespace,
			DeploymentModel:   model,
			Status:            status,
			AvailableReplicas: d.Status.AvailableReplicas,
			DesiredReplicas:   d.Status.Replicas,
		})
	}

	sort.Slice(services, func(i, j int) bool {
		if services[i].Namespace != services[j].Namespace {
			return services[i].Namespace < services[j].Namespace
		}
		return services[i].Name < services[j].Name
	})

	return &ServiceList{Services: services, TotalCount: len(services)}, nil
}

func RenderTable(w io.Writer, list *ServiceList) {
	tw := tabwriter.NewWriter(w, 0, 0, 3, ' ', 0)
	fmt.Fprintln(tw, "NAMESPACE\tNAME\tMODEL\tSTATUS\tREPLICAS")
	for _, s := range list.Services {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", s.Namespace, s.Name, s.DeploymentModel, s.Status, replicasDisplay(s))
	}
	tw.Flush()
}

func replicasDisplay(s ServiceInfo) string {
	if s.Status == "Unknown" || s.DesiredReplicas == 0 {
		return "0/0"
	}
	return fmt.Sprintf("%d/%d", s.AvailableReplicas, s.DesiredReplicas)
}

func RenderJSON(w io.Writer, list *ServiceList) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(list)
}
