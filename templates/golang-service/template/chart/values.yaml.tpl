replicaCount: 1

image:
  repository: ghcr.io/{{ owner }}/{{ repositoryName }}
  tag: latest
  pullPolicy: IfNotPresent

service:
  port: 8080

resources: {}

database:
  enabled: false
  secretName: ""
