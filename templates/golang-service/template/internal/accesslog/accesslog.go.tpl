// Package accesslog writes one structured log line per HTTP request.
package accesslog

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/{{ owner }}/{{ repositoryName }}/internal/metrics"
)

// Middleware logs every request that next handles, after it completes, at
// INFO for 1xx-3xx, WARN for 4xx and ERROR for 5xx. next must be (or wrap,
// without cloning the request) the *http.ServeMux: route is read from the
// pattern the mux matched, the same value as the metrics' route label.
// Requests whose route is in skip (e.g. "/healthz") are not logged, keeping
// probes and scrapes out of the log stream.
func Middleware(next http.Handler, logger *slog.Logger, skip ...string) http.Handler {
	skipped := make(map[string]bool, len(skip))
	for _, route := range skip {
		skipped[route] = true
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rw, r)

		route := metrics.Route(r)
		if skipped[route] {
			return
		}
		logger.LogAttrs(context.Background(), level(rw.status), "http request",
			slog.String("method", r.Method),
			// The raw path is fine in a log line (unlike a metric label),
			// but the query string isn't logged: it can carry tokens.
			slog.String("path", r.URL.Path),
			slog.String("route", route),
			slog.Int("status", rw.status),
			slog.Float64("duration_ms", float64(time.Since(start).Microseconds())/1000),
			slog.Int64("response_bytes", rw.bytes),
			slog.String("remote_addr", r.RemoteAddr),
			slog.String("user_agent", r.UserAgent()),
			slog.String("proto", r.Proto),
		)
	})
}

func level(status int) slog.Level {
	switch {
	case status >= 500:
		return slog.LevelError
	case status >= 400:
		return slog.LevelWarn
	}
	return slog.LevelInfo
}

// responseWriter captures the status code and body size a handler writes; a
// handler that never calls WriteHeader implicitly sends 200.
type responseWriter struct {
	http.ResponseWriter
	status      int
	bytes       int64
	wroteHeader bool
}

func (w *responseWriter) WriteHeader(code int) {
	if !w.wroteHeader {
		w.status = code
		w.wroteHeader = true
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *responseWriter) Write(b []byte) (int, error) {
	w.wroteHeader = true
	n, err := w.ResponseWriter.Write(b)
	w.bytes += int64(n)
	return n, err
}

// Unwrap lets http.ResponseController reach the underlying writer's
// optional interfaces (Flush, Hijack, deadlines).
func (w *responseWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}
