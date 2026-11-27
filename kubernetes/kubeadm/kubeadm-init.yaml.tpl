# Configuration kubeadm du premier control plane (rendue par scripts/node/10-init-first-cp.sh).
# API v1beta3 (Kubernetes 1.30). En 1.31, v1beta4 apparaît ; v1beta3 reste accepté.
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: ${NODE_NAME}
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: ${NODE_IP}
  # Le manifeste kube-vip est posé avant l'init.
  ignorePreflightErrors:
    - DirAvailable--etc-kubernetes-manifests
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
skipPhases:
  - addon/kube-proxy        # remplacé par Cilium (kubeProxyReplacement)
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: ${CLUSTER_NAME}
kubernetesVersion: ${K8S_VERSION}
controlPlaneEndpoint: "${API_VIP}:6443"
networking:
  podSubnet: ${POD_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
  dnsDomain: cluster.local
apiServer:
  certSANs:
    - ${API_VIP}
    - k8s-api.ows.local
    - 127.0.0.1
  extraArgs:
    authorization-mode: Node,RBAC
    audit-log-path: /var/log/kubernetes/audit.log
    audit-log-maxage: "7"
    audit-policy-file: /etc/kubernetes/audit-policy.yaml
  extraVolumes:
    - name: audit-policy
      hostPath: /etc/kubernetes/audit-policy.yaml
      mountPath: /etc/kubernetes/audit-policy.yaml
      readOnly: true
      pathType: File
    - name: audit-log
      hostPath: /var/log/kubernetes
      mountPath: /var/log/kubernetes
      pathType: DirectoryOrCreate
# Métriques lisibles par Prometheus (par défaut liées à 127.0.0.1).
controllerManager:
  extraArgs:
    bind-address: 0.0.0.0
scheduler:
  extraArgs:
    bind-address: 0.0.0.0
etcd:
  local:
    dataDir: /var/lib/etcd
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
serverTLSBootstrap: false
rotateCertificates: true
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
# Non déployé (skipPhases), conservé pour référence.
mode: ipvs
