# How to Use

This is a base Kustomization that should be imported into another project.

This Kustomization should be deployed after the hcloud-cloud-controller
Kustomization or another Kustomization that provides LoadBalancers has been
installed. Otherwise, it will have to be adapted to use either NodePort
Services or hostPort configurations for Pods (not recommended).
