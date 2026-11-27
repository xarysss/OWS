# Join d'un worker (rendu par scripts/node/11-join.sh).
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
nodeRegistration:
  name: ${NODE_NAME}
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: ${NODE_IP}
discovery:
  bootstrapToken:
    apiServerEndpoint: "${API_VIP}:6443"
    token: "${JOIN_TOKEN}"
    caCertHashes:
      - "${CA_HASH}"
