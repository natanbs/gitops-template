package main

import (
	"fmt"
	"net/http"
	"os"
)

// port returns the listen port. The k8s deploy template injects PORT
// (= CONTAINER_PORT), so overriding --container-port reaches the app without
// an image rebuild. Default matches CONTAINER_PORT in init/app.env.
func port() string {
	if p := os.Getenv("PORT"); p != "" {
		return p
	}
	return "8080"
}

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Go!")
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.ListenAndServe(":"+port(), nil)
}
