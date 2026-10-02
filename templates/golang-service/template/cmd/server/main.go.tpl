package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	_ "github.com/lib/pq"

	"github.com/{{ owner }}/{{ repositoryName }}/internal/accesslog"
	"github.com/{{ owner }}/{{ repositoryName }}/internal/metrics"
)

func main() {
	// Every line on stdout is one JSON object, so a log collector (e.g.
	// Loki's) can parse fields without a per-service regex. SetDefault also
	// routes the standard library's log package through this handler.
	logger := newLogger(os.Stdout)
	slog.SetDefault(logger)

	db := connectDB()
	if db != nil {
		defer db.Close()
	}

	logger.Info("listening", "addr", ":8080")
	if err := http.ListenAndServe(":8080", newHandler(db, logger)); err != nil {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

// newLogger returns the service's JSON logger. Every line carries `service`,
// so lines stay attributable after they leave the pod.
func newLogger(w io.Writer) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, nil)).With("service", "{{ componentName }}")
}

// probes are served but kept out of the request metrics and the access log:
// they're kubelet and Prometheus traffic, not service traffic.
var probes = []string{"/healthz", "/readyz", "/metrics"}

// endpoint is one entry in the index served at /.
type endpoint struct {
	Method      string `json:"method"`
	Path        string `json:"path"`
	Description string `json:"description"`
}

// endpoints is the service's self-description, served at /. Add an entry
// whenever you register a route on the mux in newHandler.
var endpoints = []endpoint{
	{"GET", "/", "This index: the service's name and endpoints."},
	{"GET", "/healthz", "Liveness: always 200, no dependencies checked."},
	{"GET", "/readyz", "Readiness: 503 if a configured database is unreachable."},
	{"GET", "/metrics", "Prometheus metrics: runtime, process, HTTP and database pool."},
}

// newHandler builds the service's HTTP handler. db may be nil (no database
// binding); every endpoint, /metrics included, works either way.
func newHandler(db *sql.DB, logger *slog.Logger) http.Handler {
	reg := metrics.NewRegistry()
	metrics.RegisterDB(reg, db)
	httpMetrics := metrics.NewHTTP(reg)

	mux := http.NewServeMux()

	// Register application routes on mux. Use patterns with wildcards
	// ("GET /orders/{id}") rather than parsing paths by hand: the matched
	// pattern is what the http_requests_total route label records.

	// "/{$}" matches only "/" itself; a bare "/" would catch every
	// unregistered path.
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(struct {
			Service   string     `json:"service"`
			Message   string     `json:"message"`
			Endpoints []endpoint `json:"endpoints"`
		}{
			Service:   "{{ componentName }}",
			Message:   "This is the {{ componentName }} service.",
			Endpoints: endpoints,
		})
	})
	mux.Handle("/metrics", metrics.Handler(reg))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if db == nil {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("ok: database not configured"))
			return
		}
		if err := db.PingContext(r.Context()); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintf(w, "database unreachable: %v", err)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok: database reachable"))
	})

	// Both middlewares read the route the mux matched, so the metrics
	// middleware wraps the mux directly and passes the request through as-is.
	return accesslog.Middleware(httpMetrics.Middleware(mux, probes...), logger, probes...)
}

// connectDB returns nil when the database binding isn't mounted — the
// database capability is disabled (chart's bindings.database absent), not a
// connection failure. It does not ping at startup: a fresh pod shouldn't
// crash-loop waiting on a database that's still provisioning. /readyz is
// what actually checks reachability, on demand.
func connectDB() *sql.DB {
	root := os.Getenv("SERVICE_BINDING_ROOT")
	if root == "" {
		root = "/bindings"
	}
	dir := filepath.Join(root, "database")

	host, err := readBindingFile(dir, "endpoint")
	if err != nil {
		return nil
	}

	sslmode := os.Getenv("DB_SSLMODE")
	if sslmode == "" {
		sslmode = "require"
	}
	port, _ := readBindingFile(dir, "port")
	user, _ := readBindingFile(dir, "username")
	password, _ := readBindingFile(dir, "password")
	name, _ := readBindingFile(dir, "dbname")

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port, user, password, name, sslmode,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		slog.Error("database configured but failed to open", "error", err)
		return nil
	}
	return db
}

// readBindingFile reads one key from a mounted binding directory, per the
// $SERVICE_BINDING_ROOT/<binding>/<key> file convention.
func readBindingFile(dir, name string) (string, error) {
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}
