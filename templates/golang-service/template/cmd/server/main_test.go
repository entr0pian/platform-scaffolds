package main

import (
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
	h := newHandler(db)

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
	h := newHandler(db)

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
