# Pod statique kube-vip : VIP de l'API en ARP avec élection de leader.
# Rendu par scripts/node/03-kube-vip.sh dans /etc/kubernetes/manifests/.
# Prérequis OpenStack : la VIP est dans allowed_address_pairs des ports CP
# (openstack/tofu/compute.tf).
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  hostNetwork: true
  hostAliases:
    - hostnames: ["kubernetes"]
      ip: 127.0.0.1
  containers:
    - name: kube-vip
      image: ghcr.io/kube-vip/kube-vip:${KUBE_VIP_VERSION}
      imagePullPolicy: IfNotPresent
      args: ["manager"]
      env:
        - { name: vip_arp, value: "true" }
        - { name: port, value: "6443" }
        - { name: vip_interface, value: "${IFACE}" }
        - { name: vip_cidr, value: "32" }
        - { name: dns_mode, value: "first" }
        - { name: cp_enable, value: "true" }
        - { name: cp_namespace, value: "kube-system" }
        - { name: svc_enable, value: "false" }      # les Services LoadBalancer = MetalLB
        - { name: vip_leaderelection, value: "true" }
        - { name: vip_leasename, value: "plndr-cp-lock" }
        - { name: vip_leaseduration, value: "5" }
        - { name: vip_renewdeadline, value: "3" }
        - { name: vip_retryperiod, value: "1" }
        - { name: address, value: "${API_VIP}" }
        - { name: prometheus_server, value: ":2112" }
      securityContext:
        capabilities:
          add: ["NET_ADMIN", "NET_RAW"]
      volumeMounts:
        - name: kubeconfig
          mountPath: /etc/kubernetes/admin.conf
  volumes:
    - name: kubeconfig
      hostPath:
        path: ${KCONF}
