# [ArgoCD](https://argoproj.github.io/argo-cd/)
![ArgoCD Status Indicator](https://argocd.hashbang.sh/api/badge?name=argocd)

With [KSOPS](https://github.com/viaduct-ai/kustomize-sops) integration.

# Bootstrapping

To instantiate a clean repository with a quickly-configured ArgoCD, run the
script `argocd/scripts/generate-secrets-config.sh`. This will create an SSH and
GPG key for ArgoCD to connect to the remote repository. This will also create a
.sops.yaml configuration to allow for editing secrets, and create various
secrets and configurations based on user input. The script requires several
flags to be set to generate all of the required items; you can read the source
to figure out which ones are needed. There are also some values in
values.patch.yaml that need to be changed.

## Options for `generate-secret-config.sh`

- `--generate-github-key`: Generate a new GitHub webhook key
- `--generate-sops-file`: Generate a `.sops.yaml` file from the given keys and,
  if `--generate-argocd-key` is used, the newly generated GPG key
- `--use-fingerprints`: Fingerprints used when generating `.sops.yaml`
- `--generate-argocd-key`: Generate a new GPG key for ArgoCD as well as create
  new sops-encrypted secrets for the key
- `--generate-argocd-ssh-key`: Generate a new SSH key for ArgoCD to use when
  connecting to an SSH Git origin
- `--argocd-generate-user-from-username`: Generate a users.patch.yaml based on
  a given username
- `--argocd-username`: When the above is not given, use this username when
  generating a password entry
- `--argocd-generate-password-from-input`: Give a prompt for a password and
  use that password for ArgoCD authentication, using the account from either
  `--argocd-username` or `--argocd-generate-user-from-username`
- `--argocd-generate-password`: Use the next argument to create a password in a
  fashion similar to the above

**The following options will change values in `values.patch.yaml`.**

- `--argocd-repository-url`: Remote Git origin (HTTPS or SSH) that ArgoCD will
  use to pull new updates
- `--argocd-domain-name`: Domain name to use for the Ingress resource

Assuming ArgoCD is now configured, it can be deployed to the Kubernetes
cluster. Take note of the underscores in `--enable_alpha_plugins`.

```sh
kustomize build --enable_alpha_plugins . | kubectl apply -f
```

Once ArgoCD is deployed and started, the Application resources can now be
deployed by running the above command again, and you should now be able to
deploy changes to ArgoCD through ArgoCD itself.

Before ingress-nginx is set up, ArgoCD can be accessed by running:

```sh
kubectl -n argocd port-forward service/argocd-server 5000:443
```

You can now access ArgoCD through your browser by navigating to
https://localhost:5000.

# Automatic Refreshing through GitHub Webhooks

The URL you'll want is https://argocd.example.com/api/webhook. Content type is
JSON. The secret is the one in argocd-secret.enc.yaml.

# Upgrading

1. Get the new commit hash of the release tag in the ArgoCD repository
2. Update the new commit hash in kustomization.yaml
3. Update any other places image names appear, e.g. argo-cd-import-pgp-key.patch.yaml
4. Hash lock the new images:
   - `kustomize build argocd/ | grep image:`
   - For each image, get the image hash (e.g. by visiting dockerhub)
   - Update the image hashes in kustomization.yaml
   - Run `kustomize build argocd/ | grep image:` and confirm that all images are hash-locked
