replicaCount: 1

image:
  repository: ghcr.io/{{ owner }}/{{ repositoryName }}
  tag: latest
  pullPolicy: IfNotPresent

service:
  port: 8080

# Sized for a small Go HTTP service. Limits also give the platform's
# utilization metrics (platform:container_{cpu,memory}_limit_*) a
# denominator: a container without limits has no utilization percentage.
# No LimitRange backfills them on every cluster, so set them here.
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 128Mi

bindings: {}

# Prometheus scraping. Renders a ServiceMonitor for the Service's `http`
# port, but only on clusters that serve the Prometheus Operator API
# (monitoring.coreos.com/v1), so the chart still installs anywhere else.
# `path` must match where the application serves metrics (/metrics).
observability:
  metrics:
    enabled: true
    path: /metrics
    interval: 30s

# Platform identity — set by the platform's GitOps delivery (the
# taskapp-catalog ApplicationSet passes these as Helm parameters), never
# by hand. Rendered as platform.taskapp.io/{component,environment} labels
# on the Deployment, its pods and the Service; left off when empty, so the
# chart still installs outside the platform.
platform:
  component: ""
  environment: ""
