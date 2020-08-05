#!/bin/bash
# Exit if something bad happens
set -e

extract_fingerprints() {
  gpg --list-keys $* | awk '/pub[[:space:]]/ { getline; print $1 }'
}

echo -n "GPG IDs for SOPS Encryption: "
read GPG_IDS

# Extract configured fingerprints before changing GNUPGHOME.
GPG_KEYS=($(extract_fingerprints "${GPG_IDS[@]}"))

# Set up a temporary GNUPGHOME as the user doesn't need the ArgoCD secret key.
OLD_GNUPGHOME="$GNUPGHOME"
export GNUPGHOME="$(mktemp -d)"
echo "Temporary GNUPGHOME: $GNUPGHOME"

# Generate the key used by ArgoCD to decrypt secrets
gpg --batch --generate-key <<EOF
  %echo Generating a 4096 bit RSA key
  %no-protection
  Key-Type: RSA
  Key-Length: 4096
  Name-Comment: ArgoCD Deployment and Secrets Key
  Expire-Date: 0
  %commit
  %echo Finished
EOF

# Extract secret key
SECRET_KEY="$(gpg --export-secret-keys | base64 -w0)"

# Public key is required to encrypt secrets, and may 
gpg --export > public-secrets-key.asc

# Import the key into the user's old GNUPGHOME
GNUPGHOME="$OLD_GNUPGHOME" gpg --import < public-secrets-key.asc

# Set up options for ksops to encrypt user key(s) as well as the newly
# generated ArgoCD key
KEYS=($(extract_fingerprints) ${GPG_KEYS[@]})
cat >.sops.yaml <<EOF
creation_rules:
  - encrypted_regex: '^(data|stringData)$'
    pgp: >-
EOF

for key in ${KEYS[@]}; do
  echo -n "      ${key}"
  # Test if we're not on the last key, which doesn't get a comma
  if [ "$key" != "${KEYS[-1]}" ]; then
    echo -n ","
  fi
  echo
done >> .sops.yaml

# Revert to old GNUPGHOME
export GNUPGHOME="$OLD_GNUPGHOME"

# Setting up the not-yet-encrypted secret
sops --input-type yaml --output-type yaml -e /dev/stdin > argocd/deploy-key.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: deploy-pgp-key
type: Opaque
data:
    deploy-key: $SECRET_KEY
EOF

# Generate an SSH key for ArgoCD to use; 4096 bit RSA with no passphrase
ssh-keygen -t rsa -f ./id_rsa -b 4096 -N ''
sops --input-type yaml --output-type yaml -e /dev/stdin > argocd/ssh-key.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: ssh-key
type: Opaque
stringData:
    id_rsa: |-
$(cat id_rsa | sed 's/^/        /')
    id_rsa.pub: $(cat id_rsa.pub)
EOF
rm id_rsa

# Generate a default ArgoCD user
echo -n "Username for ArgoCD: "
read ARGOCD_USERNAME

## User
cat > argocd/users.patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  # disable admin account
  accounts.admin.enabled: "false"

  # admins
  accounts.${ARGOCD_USERNAME}: apiKey,login
EOF

## Password
ARGOCD_PASSWORD_HASH="$(htpasswd -n -B -C 10 "$ARGOCD_USERNAME" | cut -d: -f2)"
sops --input-type yaml --output-type yaml -e /dev/stdin > argocd/argocd-secret.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: argocd-secret
    annotations:
        kustomize.config.k8s.io/behavior: merge
type: Opaque
stringData:
    accounts.${ARGOCD_USERNAME}.password: $(echo $ARGOCD_PASSWORD_HASH | sed "s/2y/2a/1")
EOF

## Admin Permissions
cat > argocd/argo-cd-rbac.patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
data:
  policy.default: role:readonly
  policy.csv: |
    g, ${ARGOCD_USERNAME}, role:admin
EOF

# Configure ArgoCD to read from remote GitOps repository.
echo -n "GitOps repository (git@github.com:hashbang/gitops): "
read ARGOCD_GITOPS_REPOSITORY
cat > argocd/argo-cd-repository-credentials.patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  repository.credentials: |
    - sshPrivateKeySecret:
        key: id_rsa
        name: ssh-key
      url: $ARGOCD_GITOPS_REPOSITORY
EOF

# Configure an empty notifiers.yaml for ArgoCD Notifications
sops --input-type yaml --output-type yaml -e /dev/stdin > argocd/argocd-notifications/secret.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: argocd-notifications-secret
    annotations:
        kustomize.config.k8s.io/behavior: merge
type: Opaque
stringData:
    notifiers.yaml: ""
EOF
