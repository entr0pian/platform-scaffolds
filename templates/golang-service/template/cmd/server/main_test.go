package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestWithoutDatabase(t *testing.T) {
	t.Setenv("SERVICE_BINDING_ROOT", t.TempDir())
	db := connectDB()
	if db != nil {
		t.Fatal("connectDB() returned a DB with no binding mounted")
	}
	h := newHandler(db, newLogger(io.Discard))

	if rec := get(t, h, "/healthz"); rec.Code != http.StatusOK {
		t.Errorf("/healthz = %d, want 200", rec.Code)
	}
	if rec := get(t, h, "/readyz"); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "not configured") {
		t.Errorf("/readyz = %d %q, want 200 not configured", rec.Code, rec.Body.String())
	}
	get(t, h, "/no-such-route")

	rec := get(t, h, "/metrics")
	if rec.Code != http.StatusOK {
		t.Fatalf("/metrics = %d, want 200", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Errorf("/metrics Content-Type = %q, want Prometheus text format", ct)
	}
	out := rec.Body.String()
	for _, want := range []string{
		"go_goroutines ",
		"go_memstats_heap_alloc_bytes ",
		"go_gc_duration_seconds",
		"process_cpu_seconds_total ",
		"process_resident_memory_bytes ",
		`http_requests_total{method="GET",route="unmatched",status="404"} 1`,
		`http_request_duration_seconds_count{method="GET",route="unmatched",status="404"} 1`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("/metrics missing %q", want)
		}
	}
	for _, unwanted := range []string{`route="/healthz"`, `route="/readyz"`, `route="/metrics"`, "go_sql_"} {
		if strings.Contains(out, unwanted) {
			t.Errorf("/metrics unexpectedly contains %q", unwanted)
		}
	}
}

func TestIndex(t *testing.T) {
	t.Setenv("SERVICE_BINDING_ROOT", t.TempDir())
	h := newHandler(connectDB(), newLogger(io.Discard))

	rec := get(t, h, "/")
	if rec.Code != http.StatusOK {
		t.Fatalf("/ = %d, want 200", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("/ Content-Type = %q, want application/json", ct)
	}
	var index struct {
		Service   string     `json:"service"`
		Message   string     `json:"message"`
		Endpoints []endpoint `json:"endpoints"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &index); err != nil {
		t.Fatalf("/ body is not JSON: %v", err)
	}
	if index.Service == "" || !strings.Contains(index.Message, index.Service) {
		t.Errorf("/ service = %q, message = %q", index.Service, index.Message)
	}

	// Every listed endpoint must actually be served.
	for _, e := range index.Endpoints {
		if rec := get(t, h, e.Path); rec.Code == http.StatusNotFound {
			t.Errorf("/ lists %s %s, but it returns 404", e.Method, e.Path)
		}
	}
	for _, want := range []string{"/", "/healthz", "/readyz", "/metrics"} {
		found := false
		for _, e := range index.Endpoints {
			found = found || e.Path == want
		}
		if !found {
			t.Errorf("/ does not list %s", want)
		}
	}

	// "/" is exact: other paths still 404 rather than falling through to it.
	if rec := get(t, h, "/no-such-route"); rec.Code != http.StatusNotFound {
		t.Errorf("/no-such-route = %d, want 404", rec.Code)
	}
	out := get(t, h, "/metrics").Body.String()
	if !strings.Contains(out, `http_requests_total{method="GET",route="/",status="200"}`) {
		t.Error(`/metrics missing route="/" for the index`)
	}
}

// A mounted binding pointing at a closed port: the pool exists (so its
// metrics are exposed) but the database is unreachable.
func TestWithUnreachableDatabase(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "database")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, value := range map[string]string{
		"endpoint": "127.0.0.1",
		"port":     "1",
		"username": "app",
		"password": "s3cret",
		"dbname":   "orders",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(value+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("SERVICE_BINDING_ROOT", root)
	t.Setenv("DB_SSLMODE", "disable")

	db := connectDB()
	if db == nil {
		t.Fatal("connectDB() = nil with a binding mounted")
	}
	defer db.Close()
	h := newHandler(db, newLogger(io.Discard))

	if rec := get(t, h, "/healthz"); rec.Code != http.StatusOK {
		t.Errorf("/healthz = %d, want 200", rec.Code)
	}
	if rec := get(t, h, "/readyz"); rec.Code != http.StatusServiceUnavailable {
		t.Errorf("/readyz = %d, want 503", rec.Code)
	}

	out := get(t, h, "/metrics").Body.String()
	for _, want := range []string{
		`go_sql_open_connections{db_name="database"}`,
		`go_sql_in_use_connections{db_name="database"}`,
		`go_sql_idle_connections{db_name="database"}`,
		`go_sql_wait_count_total{db_name="database"}`,
		`go_sql_wait_duration_seconds_total{db_name="database"}`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("/metrics missing %q", want)
		}
	}
	if strings.Contains(out, "s3cret") || strings.Contains(out, "orders") {
		t.Error("/metrics leaks database connection details")
	}
}

func TestAccessLog(t *testing.T) {
	t.Setenv("SERVICE_BINDING_ROOT", t.TempDir())
	var buf bytes.Buffer
	h := newHandler(connectDB(), newLogger(&buf))

	get(t, h, "/")
	get(t, h, "/healthz")
	get(t, h, "/metrics")

	out := strings.TrimSpace(buf.String())
	if strings.Count(out, "\n") != 0 {
		t.Fatalf("want exactly one log line (probes and scrapes skipped), got:\n%s", out)
	}
	var entry map[string]any
	if err := json.Unmarshal([]byte(out), &entry); err != nil {
		t.Fatalf("log line is not JSON: %q: %v", out, err)
	}
	if entry["service"] == "" || entry["service"] == nil {
		t.Errorf("log line has no service: %v", entry)
	}
	if entry["route"] != "/" || entry["status"] != float64(200) {
		t.Errorf("log line = %v, want route / status 200", entry)
	}
}
