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
