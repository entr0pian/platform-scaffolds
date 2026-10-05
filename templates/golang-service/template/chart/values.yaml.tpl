# Two pods by default, so a pod restart, node drain or rollout never leaves
# the Service without a ready endpoint.
replicaCount: 2

# Seconds a new pod must stay Ready before the Deployment counts it as
# available and moves the rollout on. Catches a pod that passes its first
# readiness check and then crashes.
minReadySeconds: 20

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

# Probe timings. startup gives the process up to periodSeconds *
# failureThreshold (60s) to answer /healthz before liveness takes over;
# readiness then checks /readyz (the database, when bound) every 5s.
probes:
  startup:
    periodSeconds: 2
    failureThreshold: 30
  readiness:
    periodSeconds: 5
    timeoutSeconds: 2
    failureThreshold: 3
  liveness:
    periodSeconds: 10
    timeoutSeconds: 2
    failureThreshold: 3

# Voluntary disruptions (node drains, cluster upgrades) evict at most one pod
# at a time. maxUnavailable rather than minAvailable, so a single-replica
# deployment can still be drained.
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

bindings: {}

# Public HTTPS endpoint: https://<component>.<environment>.<platform.domain>,
# through the cluster's AWS Load Balancer Controller (one shared ALB per
# environment) with DNS from external-dns and the certificate found in ACM by
# hostname. Rendered only inside the platform (component and environment
# set) and only in `environments`, the ones the wildcard certificate covers.
# /metrics is answered with a 404 at the ALB, so only in-cluster Prometheus
# reaches it.
ingress:
  enabled: true
  environments: [dev, prod]
  className: alb
  # Added to (and overriding) the chart's ALB annotations.
  annotations: {}

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
  # Base domain for the public hostname and the landing page's links to the
  # developer portal (platform.<domain>) and Argo CD (argocd.<domain>).
  domain: gerodimos.dev
