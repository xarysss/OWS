# Plan des slides : RETEX OWS Kube HA

Objectif : 10 à 12 slides, environ 15 minutes, puis débat. Une idée par slide, peu de texte, un visuel par slide.
Les passages entre crochets [ ] sont à compléter avec ce qui s'est vraiment passé pendant le projet.

---

### 1. Titre
- « OWS Kube HA : migrer Kubenstein d'EKS vers un Kubernetes HA en GitOps »
- Équipe (2 personnes), date, logo OWS.

### 2. Le besoin et notre réponse
- Kubenstein quitte AWS EKS. Il veut un cluster fiable, flexible, redéployable.
- Notre réponse : un produit, pas un projet unique.
- Visuel : EKS à gauche, OWS à droite, une flèche « migration ».

### 3. Architecture livrée
- Schéma : OpenStack, puis 3 CP et 3 workers (kubeadm, etcd intégré), puis Cilium, MetalLB, Rook-Ceph, Vault, Prometheus/Grafana, Velero, et ArgoCD au-dessus.
- Une phrase : « Git est la seule source de vérité. »

### 4. Notre approche GitOps
- Chaîne : OpenTofu (VM) → Ansible (kubeadm) → ArgoCD app-of-apps (tout le reste).
- Visuel : un commit qui arrive dans le cluster.
- Chiffre fort : temps de redéploiement complet chronométré [xx min].

### 5. Les étapes du projet et la gestion de projet
- Frise : validation 1+1 → HA 3+3 → GitOps → stockage → secrets → supervision → sauvegarde → upgrade 1.31.
- Kanban GitHub Projects : aucune tâche sans carte.
- Estimé contre réel : 39 j-h prévus, [xx] j-h passés. Ce qui a dérapé et pourquoi.

### 6. Difficultés techniques et solutions
Trois cas concrets, au format problème → cause → solution. Pistes :
- IP virtuelle de l'API et MetalLB sur OpenStack (allowed-address-pairs) : [solution retenue : kube-vip ou Octavia].
- Rook-Ceph : disques, placement, état HEALTH_OK : [ce qui a bloqué].
- Ordre de démarrage dans ArgoCD (CRD avant les ressources, sync waves) : [exemple].
- Upgrade 1.30 → 1.31 : [incident éventuel].

### 7. Difficultés d'organisation et de collaboration
- Cloud OpenStack partagé entre groupes : quotas, préfixe `ows-`, pas d'action hors projet.
- Travail à deux : répartition, revues, conflits Git.
- Ce qui est resté non résolu, avec une piste d'amélioration.

### 8. Choix techniques justifiés
Tableau à 4 colonnes : choix / pourquoi / alternative envisagée / le referait-on ?
- kubeadm / imposé, comprendre le cluster / k3s, RKE2 / oui
- Cilium / eBPF, politiques réseau, Hubble / Calico, Flannel / [ ]
- Rook-Ceph (Operator) / stockage répliqué + S3 / Longhorn, Cinder CSI / [ ]
- ArgoCD app-of-apps / visibilité, imposé / Flux / [ ]
- Vault + External Secrets / rien en clair dans Git / Sealed Secrets, SOPS / [ ]
- Helm ou Operator / Helm pour les composants sans état, Operator pour ce qui a un cycle de vie (Ceph) / manifests bruts / oui

### 9. Le produit : prix et positionnement
- Trois offres : Essentiel 990 €, **Pro 1 490 €**, Premium 2 490 € par mois.
- TCO sur 3 ans pour Kubenstein : ≈ 69 500 € avec OWS contre ≈ 87 800 € avec EKS (−21 %).
- Honnêteté : EKS est moins cher en infrastructure brute ; OWS gagne dès que l'exploitation d'EKS dépasse 2,4 j/mois.
- Source : dossier-commercial.md.

### 10. Avantages et limites
- Deux colonnes, 3 points chacune.
- Avantages : plateforme complète exploitée, pas d'enfermement, coût prévisible.
- Limites : pas d'autoscaling de nœuds, une seule région, petite équipe.

### 11. Synthèse : ce que nous avons appris
- Compétences renforcées : Kubernetes en profondeur (etcd, certificats, upgrade), IaC, GitOps, stockage distribué, gestion des secrets, chiffrage d'une offre.
- À refaire autrement : [ex. automatiser plus tôt, tester la restauration dès le début, mesurer le temps passé dès le premier jour].

### 12. Questions pour lancer le débat
- « Pour un client de cette taille, un Kubernetes managé est-il toujours plus rentable qu'un cluster auto-hébergé ? »
- « Rook-Ceph dans le cluster ou stockage externe : où placer la limite ? »
- « Helm ou Operator : quel critère utiliseriez-vous ? »
- « Une équipe de 2 peut-elle vendre un SLA de 99,9 % ? »

---

## Conseils de présentation
- Une démonstration courte : un commit qui modifie une application, ArgoCD qui synchronise, le tableau Grafana qui réagit.
- Garder en annexe (slides cachées) : tableau détaillé des coûts, procédure d'upgrade, captures Grafana.
- Préparer une réponse aux critiques prévisibles : l'hypothèse des 4 j/mois sur EKS, la tenue du SLA à deux personnes, le site unique.
