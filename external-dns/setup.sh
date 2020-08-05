#!/bin/sh
# Exit if something bad happens
set -e

cat <<EOF
Service providers supported:
- AWS (aws)
- CloudFlare (cloudflare)
EOF
echo
echo -n "Please select your provider: "
read DNS_PROVIDER
export DNS_PROVIDER

case $DNS_PROVIDER in
  aws)
    # TODO test
    echo "This is untested. Bug Ryan to merge this into #! official."
    exit 1

    # template for AWS dns provider
    echo -n "Please enter the AWS region of the Route53 zone:"
    read AWS_DEFAULT_REGION
    echo -n "Please input your IAM access and secret key, space delimited: "
    read AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

    # Export for usage in envsubst
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
    envsubst < setup_templates/external-dns-aws.yaml > external-dns-aws.yaml
    envsubst < setup_templates/external-dns-aws-secret.yaml | \
      sops --input-type yaml --output-type yaml -e /dev/stdin > external-dns-aws-secret.enc.yaml
    ;;

  cloudflare)
    # template for CloudFlare dns provider
    echo -n "Please enter the CloudFlare API Email and Key, space delimited: "
    read CF_API_EMAIL CF_API_KEY
    
    # Export for usage in envsubst
    export CF_API_EMAIL CF_API_KEY
    envsubst < setup_templates/external-dns-cloudflare.yaml > external-dns-cloudflare.yaml
    envsubst < setup_templates/external-dns-cloudflare-secret.yaml | \
      sops --input-type yaml --output-type yaml -e /dev/stdin > external-dns-cloudflare-secret.enc.yaml
    ;;

  *)
    echo "DNS provider not found: $DNS_PROVIDER"
    exit 1
    ;;
esac

envsubst < setup_templates/secret-generator.yaml > secret-generator.yaml
envsubst < setup_templates/kustomization.yaml > kustomization.yaml
envsubst < setup_templates/resources.yaml > resources.yaml
