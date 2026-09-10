apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: {{ componentName }}
  description: {{ componentName }} service
  annotations:
    github.com/project-slug: {{ owner }}/{{ repositoryName }}
spec:
  type: service
  lifecycle: experimental
  owner: {{ componentOwner }}
