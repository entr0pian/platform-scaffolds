package metrics

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// unmatchedRoute labels requests that no registered pattern handled (404s,
// 405s). Collapsing them into one value is what keeps scanners and typos
// from minting a new series per URL.
const unmatchedRoute = "unmatched"

// HTTP records http_requests_total and http_request_duration_seconds,
// labelled by method, route and status.
type HTTP struct {
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
}

// NewHTTP creates the HTTP request metrics and registers them with reg.
func NewHTTP(reg prometheus.Registerer) *HTTP {
	labels := []string{"method", "route", "status"}
	m := &HTTP{
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP requests handled, by method, route pattern and status code.",
		}, labels),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request latency, by method, route pattern and status code.",
			Buckets: prometheus.DefBuckets,
		}, labels),
	}
	reg.MustRegister(m.requests, m.duration)
	return m
}

// Middleware instruments every request that mux handles. It must wrap the
// *http.ServeMux directly: the route label is the pattern the mux matched
// (r.Pattern, e.g. "/orders/{id}"), never the raw URL path, so
// the label's values are bounded by the routes the service registers.
// Requests whose matched route is in skip (e.g. "/healthz") are not
// recorded, keeping probes and scrapes out of the traffic metrics.
func (m *HTTP) Middleware(mux *http.ServeMux, skip ...string) http.Handler {
	skipped := make(map[string]bool, len(skip))
	for _, route := range skip {
		skipped[route] = true
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}

		// ServeMux sets r.Pattern on this same *Request once it has
		// matched, so it's readable after ServeHTTP returns.
		mux.ServeHTTP(sw, r)

		route := Route(r)
		if skipped[route] {
			return
		}
		labels := prometheus.Labels{
			"method": normalizeMethod(r.Method),
			"route":  route,
			"status": strconv.Itoa(sw.status),
		}
		m.requests.With(labels).Inc()
		m.duration.With(labels).Observe(time.Since(start).Seconds())
	})
}

// Route reduces r.Pattern ("[METHOD ][HOST]/path") to its path part, so
// "GET /orders/{id}" becomes "/orders/{id}"; the method is its own label.
// It is only meaningful after the mux has served r. Exported so the access
// log records the same route value as the metrics, letting a log line and
// its series be joined on it.
func Route(r *http.Request) string {
	// For CONNECT, ServeMux may report the raw request path as the
	// pattern — not bounded, so don't trust it.
	if r.Method == http.MethodConnect {
		return unmatchedRoute
	}
	i := strings.IndexByte(r.Pattern, '/')
	if i < 0 {
		return unmatchedRoute
	}
	// "{$}" only anchors a pattern to an exact path: "GET /{$}" is "/".
	return strings.TrimSuffix(r.Pattern[i:], "{$}")
}

// normalizeMethod maps anything outside the standard methods to "OTHER":
// the method is client-controlled, so it can't be used as a label verbatim.
func normalizeMethod(method string) string {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut,
		http.MethodPatch, http.MethodDelete, http.MethodOptions:
		return method
	}
	return "OTHER"
}

// statusWriter captures the status code a handler writes; a handler that
// never calls WriteHeader implicitly sends 200.
type statusWriter struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (w *statusWriter) WriteHeader(code int) {
	if !w.wroteHeader {
		w.status = code
		w.wroteHeader = true
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	w.wroteHeader = true
	return w.ResponseWriter.Write(b)
}

// Unwrap lets http.ResponseController reach the underlying writer's
// optional interfaces (Flush, Hijack, deadlines).
func (w *statusWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}
