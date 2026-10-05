# {{ componentName }}

Generated from the `golang-service` scaffold in [platform-scaffolds](https://github.com/entr0pian/platform-scaffolds).

## Development

```
make build
make test
make run
```

## Endpoints

- `GET /` — index: JSON with the service name and the endpoints below. It reads
  from the `endpoints` list in `cmd/server/main.go`; add to that list whenever you
  register a route.
- `GET /healthz` — liveness; always `200`, no dependencies checked.
- `GET /readyz` — readiness; `200` if the database is unconfigured or reachable,
  `503` if `bindings.database` is set but the database can't be reached.
- `GET /metrics` — Prometheus metrics (see below).

## Metrics

`/metrics` serves, in the Prometheus text format:

| Metric | Source |
|---|---|
| `go_*` | Go runtime: goroutines, memory, GC |
| `process_*` | Process CPU, memory, file descriptors |
| `http_requests_total{method,route,status}` | Every request except `/healthz`, `/readyz`, `/metrics` |
| `http_request_duration_seconds{method,route,status}` | Histogram, same requests |
| `go_sql_*{db_name="database"}` | Connection pool (`db.Stats()`), only when a database binding is mounted |

Instrumentation lives in `internal/metrics`. The HTTP middleware wraps the
`http.ServeMux` in `cmd/server/main.go`, and `route` is the **pattern the mux
matched**, not the request path: register `GET /orders/{id}` and every order
lands under `route="/orders/{id}"`. Requests matching no pattern (404/405) share
`route="unmatched"`, and non-standard methods become `method="OTHER"`, so no
client can create unbounded series. Keep it that way: register routes on the mux
with `{wildcards}`, and don't add labels carrying IDs, IPs or raw paths.

Kubernetes-level metrics (pod CPU/memory, restarts, replicas) aren't exposed
here. They come from the cluster's own monitoring stack.

## Logs

The service logs to stdout, one JSON object per line (`log/slog`'s JSON
handler), so a collector such as Loki can parse fields without a per-service
regex. Every line has `time`, `level`, `msg` and `service`. Log through `slog`
(`slog.Info("order created", "order_id", id)`); the standard library's `log`
package is routed through the same handler too.

Every request except `/healthz`, `/readyz` and `/metrics` gets one access log
line once it completes, from `internal/accesslog`:

```json
{"time":"2026-10-02T17:18:33.266900054+03:00","level":"INFO","msg":"http request","service":"{{ componentName }}","method":"GET","path":"/","route":"/","status":200,"duration_ms":0.18,"response_bytes":482,"remote_addr":"10.0.1.7:41932","user_agent":"k6/2.3.0","proto":"HTTP/1.1"}
```

`level` follows the status: `INFO` below 400, `WARN` for 4xx, `ERROR` for 5xx.
`route` is the same value as the metrics' `route` label, so a log line can be
matched to its series; `path` is the raw request path. The query string is never
logged, since it can carry tokens.

## Deployment

Helm chart lives in `chart/`. It sets CPU/memory requests and limits by
default (`resources` in `values.yaml`); tune them to the service's real usage,
but keep limits set: the platform's utilization metrics divide usage by the
container's limit, so a container without one has no utilization percentage.

The chart runs `replicaCount: 2` pods and only counts a new pod as available
once it has passed `/readyz` and stayed Ready for `minReadySeconds` (20s).
Rollouts add a pod before removing one (`maxSurge: 1`, `maxUnavailable: 0`),
so the Service never has fewer ready pods than `replicaCount`. A startup probe
on `/healthz` gives the process up to 60s to come up before liveness checks
start; timings are under `probes` in `values.yaml`. A PodDisruptionBudget
(`maxUnavailable: 1`) keeps node drains from evicting more than one pod at a
time.

`helm unittest chart` runs its tests
([helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin).

With `observability.metrics.enabled` (default `true`), the chart adds a
`ServiceMonitor` for the Service's `http` port, but only when the cluster serves
the Prometheus Operator API (`monitoring.coreos.com/v1`), so the chart still
installs on clusters without it. The ServiceMonitor maps the Service's
`platform.taskapp.io/{component,environment}` labels to `component` and
`environment` on every series, so metrics can be queried as
`http_requests_total{component="{{ componentName }}", environment="dev"}`. The
platform sets those labels at deploy time; the application never sees them.

**Prometheus selector assumption.** The ServiceMonitor carries no
Prometheus-specific selector label (such as `release: <name>`). Prometheus must be
configured to select ServiceMonitors in any namespace, e.g. for
kube-prometheus-stack:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # serviceMonitorSelector: {}
    serviceMonitorNamespaceSelector: {}
```
