#!/bin/bash
set -ex

extract_fingerprints() {
  gpg --list-keys "$@" | awk '/pub[[:space:]]/ { getline; print $1 }'
}

argocd_generate_key=false
argocd_generate_ssh_key=false
argocd_default_username=""
argocd_generate_username=""
argocd_generate_password=""
argocd_repository_url=""
argocd_domain_name=""

sops_generate_file=false
sops_key_ids=()
sops_fingerprints=()

github_generate_key=false

while [ "$1" != "" ]; do
  flag="$1"
  shift
  case $flag in
    --generate-github-key)
      github_generate_key=true
      ;;
    --generate-sops-file)
      sops_generate_file=true
      ;;
    --use-fingerprints)
      [[ $(echo "$1" | head -c 1) = "-" ]] && \
        echo "Missing value to $flag (found flag)" && exit 1
      [[ "$1" = "" ]] && \
        echo "Missing value to $flag (found empty)" && exit 1
      sops_key_ids=(${sops_key_ids[@]} $1)
      # while not empty string or flag
      while [[ ! $(echo "$2" | head -c 1) = "-" ]] && \
            [[ ! "$1" = "" ]]; do
        sops_key_ids=(${sops_key_ids[@]} $2)
        shift
      done
      shift
      sops_fingerprints="$(extract_fingerprints "${sops_key_ids[@]}")"
      ;;
    --generate-argocd-key)
      argocd_generate_key=true
      ;;
    --generate-argocd-ssh-key)
      argocd_generate_ssh_key=true
      ;;
    --argocd-generate-user-from-username)
      argocd_generate_username="$1"
      shift
      ;;
    --argocd-username)
      argocd_default_username="$1"
      shift
      ;;
    --argocd-generate-password)
      argocd_generate_password="$1"
      shift
      ;;
    --argocd-generate-password-from-input)
      # -p is a filthy bashism
      read -p "ArgoCD password: " argocd_generate_password
      ;;
    --argocd-repository-url)
      argocd_repository_url="$1"
      shift
      ;;
    --argocd-domain-name)
      argocd_domain_name="$1"
      shift
      ;;
    *)
      echo "flag|option not known: $flag"
      exit 1
      ;;
  esac
done


if $($argocd_generate_key); then
old_gnupghome="$GNUPGHOME"
export GNUPGHOME="$(mktemp -d)"

gpg --batch --generate-key <<EOF
  %echo Generating a 4096 bit RSA key
  %no-protection
  Key-Type: RSA
  Key-Length: 4096
  Name-Comment: ArgoCD Deployments and Secrets Key
  Expire-Date: 0
  %commit
  %echo Finished generating key
EOF

secret_key="$(gpg --export-secret-keys | base64 -w0)"
gpg --export > public-secret-key.asc
echo "Public GPG key exported to: public-secret-key.asc"

GNUPGHOME="$old_gnupghome" gpg --import < public-secret-key.asc
echo "Imported new ArgoCD public key"

sops_fingerprints=(${sops_fingerprints} $(extract_fingerprints))
if $($sops_generate_file); then
  echo "Adding new key to SOPS config"
else
  echo "New key is not added to sops config by default. Please import the key"
  echo "located in public-secret-key.asc and add the fingerprint to your"
  echo ".sops.yaml file to use it with sops|ksops."
fi
export GNUPGHOME="$old_gnupghome"

# Setting up the encrypted secret containing the key
sops --input-type yaml --output-type yaml -e /dev/stdin > argocd/deploy-key.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: deploy-pgp-key
type: Opaque
data:
    deploy-key: $secret_key
EOF
fi # argocd_generate_key

if [[ ! "$argocd_generate_username" = "" ]]; then
cat > argocd/users.patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  # disable admin account
  accounts.admin.enabled: "false"

  # admins
  accounts.${argocd_generate_username}: apiKey,login
EOF
cat > argocd/argo-cd-rbac.patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
data:
  policy.default: role:readonly
  policy.csv: |
    g, ${argocd_generate_username}, role:admin
EOF
fi # argocd_default_username

if [[ ! "$argocd_generate_password" = "" ]]; then
argocd_username="${argocd_generate_username:-$argocd_default_username}"
argocd_password_hash="$(htpasswd -nb -B -C 10 "${argocd_username}" "${argocd_generate_password}" | cut -d: -f2)"
sops --input-type yaml --output-type yaml -e /dev/stdin > argocd/argocd-secret.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  annotations:
    kustomize.config.k8s.io/behavior: merge
type: Opaque
stringData:
  accounts.${argocd_username}.password: $(echo $argocd_password_hash | sed "s/2y/2a/1")
EOF
fi # argocd_default_password

if $($argocd_generate_ssh_key); then
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
fi # argocd_generate_ssh_key

if [[ ! "$argocd_repository_url" = "" ]]; then
# Configure ArgoCD to read from remote GitOps repository.
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
      url: $argocd_repository_url
EOF
fi # argocd_repository_url

if $($sops_generate_file); then
# Set up options for ksops to encrypt user key(s) as well as the newly
# generated ArgoCD key
KEYS=($(extract_fingerprints) ${GPG_KEYS[@]})
cat >.sops.yaml <<EOF
creation_rules:
  - encrypted_regex: '^(data|stringData)$'
    pgp: >-
EOF
for key in ${sops_fingerprints[@]}; do
  echo -n "      ${key}"
  # Test if we're not on the last key, which doesn't get a comma
  if [ "$key" != "${sops_fingerprints[-1]}" ]; then
    echo -n ","
  fi
  echo
done >> .sops.yaml
fi # sops_generate_file | sops_fingerprints

if $($github_generate_key); then
cat > argocd/argocd-github-secret.enc.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  annotations:
    kustomize.config.k8s.io/behavior: merge
type: Opaque
stringData:
  # GitHub integration
  webhook.github.secret: $(pwgen 24 1)
EOF
fi
