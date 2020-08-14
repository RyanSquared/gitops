# cert-manager
![Cert-Manager Status Indicator](https://argocd.hashbang.sh/api/badge?name=cert-manager)

Sets up [cert-manager](https://cert-manager.io/) to automatically issue TLS certificates.

Will need to run the CRD import (cert-manager-custom-resource-definitions.yaml)
manually due to ArgoCD not having a recent enough kubectl.
