package accesslog

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestServer(buf *bytes.Buffer) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /users/{id}", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("user " + r.PathValue("id")))
	})
	mux.HandleFunc("GET /boom", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {})
	return Middleware(mux, slog.New(slog.NewJSONHandler(buf, nil)), "/healthz")
}

// lines decodes every log line, failing the test if any isn't a JSON object.
func lines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if line == "" {
			continue
		}
		var entry map[string]any
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			t.Fatalf("log line is not JSON: %q: %v", line, err)
		}
		out = append(out, entry)
	}
	return out
}

func TestLogsRequestDetails(t *testing.T) {
	var buf bytes.Buffer
	h := newTestServer(&buf)

	req := httptest.NewRequest(http.MethodGet, "/users/42?token=secret", nil)
	req.Header.Set("User-Agent", "test-agent/1.0")
	h.ServeHTTP(httptest.NewRecorder(), req)

	got := lines(t, &buf)
	if len(got) != 1 {
		t.Fatalf("got %d log lines, want 1", len(got))
	}
	e := got[0]
	for key, want := range map[string]any{
		"level":          "INFO",
		"msg":            "http request",
		"method":         "GET",
		"path":           "/users/42",
		"route":          "/users/{id}",
		"status":         float64(200),
		"response_bytes": float64(len("user 42")),
		"user_agent":     "test-agent/1.0",
		"proto":          "HTTP/1.1",
	} {
		if e[key] != want {
			t.Errorf("%s = %v, want %v", key, e[key], want)
		}
	}
	for _, key := range []string{"time", "duration_ms", "remote_addr"} {
		if _, ok := e[key]; !ok {
			t.Errorf("missing %s", key)
		}
	}
	if strings.Contains(buf.String(), "secret") {
		t.Error("query string leaked into the access log")
	}
}

func TestLevelFollowsStatus(t *testing.T) {
	var buf bytes.Buffer
	h := newTestServer(&buf)

	for _, target := range []string{"/no-such-route", "/boom"} {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, target, nil))
	}

	got := lines(t, &buf)
	if len(got) != 2 {
		t.Fatalf("got %d log lines, want 2", len(got))
	}
	if got[0]["level"] != "WARN" || got[0]["status"] != float64(404) || got[0]["route"] != "unmatched" {
		t.Errorf("404: %v", got[0])
	}
	if got[1]["level"] != "ERROR" || got[1]["status"] != float64(500) || got[1]["route"] != "/boom" {
		t.Errorf("500: %v", got[1])
	}
}

func TestSkipsProbes(t *testing.T) {
	var buf bytes.Buffer
	h := newTestServer(&buf)

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if buf.Len() != 0 {
		t.Errorf("probe was logged: %s", buf.String())
	}
}
