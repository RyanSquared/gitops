# Hashbang GitOps

## About

This repository contains the configuration for our Kubernetes cluster.
Each folder contains an "application" that is deployed into the cluster.

Deployment is done with a self-managed [ArgoCD](https://argoproj.github.io/argo-cd/) instance.
Secrets are encrypted in this repository using [SOPS](https://github.com/mozilla/sops) and applied via [KSOPS](https://github.com/viaduct-ai/kustomize-sops).

If you'd like to change anything about hashbang's infrastructure, please send a PR!


# Deployment

Deployment assumes you're on a Kubernetes system with Cilium and CoreDNS
already installed, with no other Applications configured. If you have any
applications or deployments configured that fill the need of resources, such
as a service-provided ingress, this guide is not meant to handle those, but
you should be able to avoid setting up the GitOps copy of the application or
deployment.

## Preparing ArgoCD for First Deployment

Requisites for first deployment:

- [sops](https://github.com/mozilla/sops)
- [ksops](https://github.com/viaduct-ai/kustomize-sops)
- [htpasswd](https://httpd.apache.org/docs/2.4/programs/htpasswd.html)
<!-- - [helm](https://github.com/helm/helm) (ingress-nginx) -->

**NOTE:** You should not need the above tools after this step.

### Building a Deployment Decryption Key

ArgoCD needs a key to decrypt any secrets (via ksops) that will be deployed, so
we will use GPG to generate the key, and sops to store the key in a Secret.


After running `argocd/setup.sh`, the following changes have been made:

- You now have an ArgoCD Deployment key.
- You now have a .sops.yaml configured with the above key, and your keys.
- You now have an argocd/deploy-key.enc.yaml, storing the secret key matching
  the above key.
- You now have an argocd/ssh-key.enc.yaml, storing an SSH key that can be used
  to connect to a Git repository.

## Common Tasks

### Adding New Admin(s)

Add the new admin's PGP key to `.sops.yaml`, then run:

```sh
find . -name '*.enc.yaml' | while read file; do
	sops updatekeys -y $file
done
```

Create a new argocd local user for the admin (`argocd/users.patch.yaml`).
Add the new user to the admin group (`argocd/argo-cd-rbac.patch.yaml`).
Have the new user create a password for accessing argocd and hash it with e.g. `htpasswd -n -B -C 10 adminusername`. Add it to `argocd/argocd-secret.enc.yaml`.

Have the new user create a password for accessing metrics and hash it with e.g. `htpasswd -n -B -C 10 adminusername`. Add it to `monitoring/user-auth.enc.yaml`.

Add the admin's PGP key to `mtls/files/admin_seeds/` (and update the list in `mtls/kustomization.yaml`)
