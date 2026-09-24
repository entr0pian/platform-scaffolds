replicaCount: 1

image:
  repository: ghcr.io/{{ owner }}/{{ repositoryName }}
  tag: latest
  pullPolicy: IfNotPresent

service:
  port: 8080

resources: {}

bindings: {}

# Platform identity — set by the platform's GitOps delivery (the
# taskapp-catalog ApplicationSet passes these as Helm parameters), never
# by hand. Rendered as platform.taskapp.io/{component,environment} labels
# on the Deployment, its pods and the Service; left off when empty, so the
# chart still installs outside the platform.
platform:
  component: ""
  environment: ""
