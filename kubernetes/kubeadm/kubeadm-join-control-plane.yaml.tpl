# Join d'un control plane supplémentaire (rendu par scripts/node/11-join.sh).
# Jeton et clé de certificats injectés à l'exécution, fichier détruit après usage.
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
controlPlane:
  localAPIEndpoint:
    advertiseAddress: ${NODE_IP}
    bindPort: 6443
  certificateKey: "${CERT_KEY}"
