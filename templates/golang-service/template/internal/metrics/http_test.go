package metrics

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func newTestServer(t *testing.T) (*HTTP, *prometheus.Registry, http.Handler) {
	t.Helper()
	reg := prometheus.NewRegistry()
	m := NewHTTP(reg)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /users/{id}", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(r.PathValue("id")))
	})
	mux.HandleFunc("POST /users", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {})

	return m, reg, m.Middleware(mux, "/healthz")
}

func serve(h http.Handler, method, target string) {
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(method, target, nil))
}

func TestRouteLabelIsPatternNotPath(t *testing.T) {
	m, reg, h := newTestServer(t)

	serve(h, http.MethodGet, "/users/928471")
	serve(h, http.MethodGet, "/users/42")

	if got := testutil.ToFloat64(m.requests.WithLabelValues("GET", "/users/{id}", "200")); got != 2 {
		t.Fatalf(`http_requests_total{route="/users/{id}"} = %v, want 2`, got)
	}
	if n := testutil.CollectAndCount(m.requests); n != 1 {
		t.Fatalf("http_requests_total has %d series, want 1", n)
	}
	out := gatherText(t, reg)
	if strings.Contains(out, "928471") {
		t.Fatalf("raw path leaked into metrics:\n%s", out)
	}
}

func TestExactMatchPatternLabel(t *testing.T) {
	reg := prometheus.NewRegistry()
	m := NewHTTP(reg)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {})
	h := m.Middleware(mux)

	serve(h, http.MethodGet, "/")

	if got := testutil.ToFloat64(m.requests.WithLabelValues("GET", "/", "200")); got != 1 {
		t.Fatalf(`http_requests_total{route="/"} = %v, want 1`, got)
	}
}

func TestStatusLabel(t *testing.T) {
	m, _, h := newTestServer(t)

	serve(h, http.MethodPost, "/users")

	if got := testutil.ToFloat64(m.requests.WithLabelValues("POST", "/users", "201")); got != 1 {
		t.Fatalf(`http_requests_total{status="201"} = %v, want 1`, got)
	}
}

func TestUnmatchedRequestsCollapse(t *testing.T) {
	m, _, h := newTestServer(t)

	serve(h, http.MethodGet, "/wp-admin")
	serve(h, http.MethodGet, "/.env")
	serve(h, http.MethodDelete, "/users/1") // 405: pattern exists for GET only

	if got := testutil.ToFloat64(m.requests.WithLabelValues("GET", unmatchedRoute, "404")); got != 2 {
		t.Fatalf(`404s under route="unmatched" = %v, want 2`, got)
	}
	if got := testutil.ToFloat64(m.requests.WithLabelValues("DELETE", unmatchedRoute, "405")); got != 1 {
		t.Fatalf(`405s under route="unmatched" = %v, want 1`, got)
	}
}

func TestNonStandardMethodIsOther(t *testing.T) {
	m, _, h := newTestServer(t)

	serve(h, "FOOBAR", "/users/1")

	if got := testutil.ToFloat64(m.requests.WithLabelValues("OTHER", unmatchedRoute, "405")); got != 1 {
		t.Fatalf(`http_requests_total{method="OTHER"} = %v, want 1`, got)
	}
}

func TestSkippedRoutesNotRecorded(t *testing.T) {
	m, _, h := newTestServer(t)

	serve(h, http.MethodGet, "/healthz")

	if n := testutil.CollectAndCount(m.requests); n != 0 {
		t.Fatalf("skipped route recorded %d series, want 0", n)
	}
}

func TestDurationHistogram(t *testing.T) {
	_, reg, h := newTestServer(t)

	serve(h, http.MethodGet, "/users/1")

	out := gatherText(t, reg)
	for _, want := range []string{
		`http_request_duration_seconds_bucket{method="GET",route="/users/{id}",status="200",le="+Inf"} 1`,
		`http_request_duration_seconds_count{method="GET",route="/users/{id}",status="200"} 1`,
		`# TYPE http_request_duration_seconds histogram`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// gatherText renders reg in the exposition format, as /metrics serves it.
func gatherText(t *testing.T, reg *prometheus.Registry) string {
	t.Helper()
	rec := httptest.NewRecorder()
	Handler(reg).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/metrics status = %d", rec.Code)
	}
	return rec.Body.String()
}
