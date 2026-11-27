# Dossier commercial OWS : Kubernetes HA hébergé

Client : **Kubenstein Inc** · Fournisseur : **OWS** · Version 1.0 du 27/11/2026

> Tous les montants sont en euros HT. Les prix publics étant affichés en dollars, le taux retenu est **1 $ = 0,90 €** (hypothèse à ajuster le jour de la soutenance). Les prix relevés le 27/11/2026 sont listés dans la partie « Sources ». Les autres chiffres sont des hypothèses OWS signalées comme telles.

---

## 1. Résumé

Kubenstein fait tourner ses applications sur AWS EKS. OWS lui propose de les migrer vers **OWS Kube HA**, un cluster Kubernetes haute disponibilité livré clé en main, entièrement décrit dans un dépôt Git et redéployable en une seule procédure.

| | AWS EKS (actuel) | OWS Kube HA, offre Pro |
|---|---|---|
| Coût mensuel affiché | ≈ 640 € d'infrastructure | 1 490 € tout compris |
| Coût mensuel réel pour le client (TCO) | ≈ 2 440 € (infra + ≈ 4 j/mois d'exploitation interne) | ≈ 1 715 € (abonnement + ≈ 0,5 j/mois de suivi) |
| Coût sur 3 ans | ≈ 87 800 € | ≈ 69 500 € (mise en service incluse) |
| Dépendance fournisseur | Forte (IAM, EBS, ELB, CloudWatch) | Faible : briques open source, cluster portable |

**Message clé :** EKS ne gère que le control plane. Le stockage, le réseau, la supervision, les sauvegardes, les secrets et les montées de version restent à la charge du client. OWS vend un cluster **déjà équipé et exploité**. Sur l'infrastructure brute, EKS est moins cher. OWS devient rentable pour le client dès que l'exploitation d'EKS lui demande plus de **2,4 jours par mois** (voir 5.3).

---

## 2. L'offre

### 2.1 Ce qui est livré

| Brique | Outil | Mode d'installation | Rôle |
|---|---|---|---|
| Infrastructure | OpenStack + OpenTofu | IaC versionnée | VM, réseau, groupes de sécurité, volumes |
| Cluster | kubeadm 1.30, puis 1.31 | Ansible | 3 control planes, 3 workers, etcd intégré |
| Réseau | Cilium | Helm | CNI eBPF, politiques réseau, observabilité Hubble |
| Exposition | MetalLB | Helm | IP de service sans load balancer propriétaire |
| Stockage | Rook-Ceph | Operator (Helm) | Volumes répliqués 3 fois, stockage objet S3 |
| GitOps | ArgoCD (app-of-apps) | Helm | Tout changement passe par Git |
| Secrets | Vault + External Secrets | Helm | Aucun secret en clair dans Git |
| Supervision | Prometheus + Grafana | Helm (kube-prometheus-stack) | Métriques, alertes, tableau de bord personnalisé |
| Sauvegarde | Velero | Helm | Sauvegarde et restauration des ressources et volumes |

### 2.2 Ce qui fait un produit (et pas un projet unique)

- **Redéployable :** `tofu apply` puis le playbook Ansible, puis ArgoCD synchronise le reste. Même procédure pour chaque client, seules les variables changent.
- **Industrialisé :** l'investissement de R&D (39 jours, voir 4.1) est payé une fois. Chaque nouveau client ne coûte que la mise en service.
- **Portable :** aucune brique propriétaire, le cluster tourne sur n'importe quel OpenStack, sur du matériel nu ou chez un autre hébergeur.
- **Traçable :** le tableau Kanban, l'historique Git et ArgoCD montrent qui a changé quoi et quand.

---

## 3. Grille tarifaire

### 3.1 Abonnements mensuels (par cluster 3 CP + 3 workers)

| | **Essentiel** | **Pro** (recommandé) | **Premium** |
|---|---|---|---|
| Prix mensuel HT | **990 €** | **1 490 €** | **2 490 €** |
| Disponibilité de l'API (SLA) | 99,5 % | 99,9 % | 99,95 % |
| Support | Jours ouvrés, réponse J+1 | Jours ouvrés 9 h-18 h, réponse < 4 h | 24 h/24, 7 j/7, réponse < 1 h |
| Sauvegardes Velero | Quotidiennes, 7 jours | Quotidiennes, 30 jours, hors cluster | Toutes les 6 h, 90 jours, hors site |
| Test de restauration | Semestriel | Trimestriel | Mensuel + plan de reprise testé |
| Montées de version Kubernetes | 1 par an | Chaque version mineure (≈ 3 par an) | Chaque version mineure + correctifs sous 72 h |
| Supervision | Tableau Grafana | Tableau + alertes + rapport mensuel | Tableau + alertes + revue mensuelle |
| Pénalité si SLA non tenu | 5 % | 10 % | 20 % du mois |

### 3.2 Prestations ponctuelles

| Prestation | Détail | Prix HT |
|---|---|---|
| **Mise en service + migration Kubenstein** | 12 jours × 650 € (détail en 4.3) | **7 800 €** |
| Mise en service seule (nouveau client, sans migration) | 4 jours × 650 € | 2 600 € |
| Journée d'expertise ou de formation | Taux journalier | 650 € / jour |
| Worker supplémentaire (4 vCPU, 16 Go, 100 Go Ceph) | Ajouté à l'abonnement | + 190 € / mois |

Le taux de 650 € par jour est dans la fourchette du marché français pour un ingénieur DevOps/Kubernetes en prestation (environ 500 à 750 €).

### 3.3 Proposition pour Kubenstein

| Poste | Année 1 | Années 2 et 3 (par an) | Total 3 ans |
|---|---|---|---|
| Mise en service + migration | 7 800 € | 0 € | 7 800 € |
| Abonnement Pro (12 × 1 490 €) | 17 880 € | 17 880 € | 53 640 € |
| **Total facturé** | **25 680 €** | **17 880 €** | **61 440 €** |

---

## 4. Comment le prix est construit (coûts OWS)

### 4.1 Coût de R&D, mesuré par la gestion de projet

Chaque étape du Kanban est estimée en jours-homme (j-h). C'est cette estimation, comparée au temps réellement passé, qui sert à fixer les prix.

| # | Étape Kanban | j-h estimés |
|---|---|---|
| 0 | Cadrage, Kanban, structure du dépôt | 1 |
| 1 | Outils (client OpenStack, OpenTofu, Ansible, kubectl, Helm) | 1 |
| 2 | Audit du projet OpenStack (quotas, réseaux) | 1 |
| 3 | Infrastructure OpenTofu | 4 |
| 4 | Validation 1 CP + 1 worker | 3 |
| 5 | Haute disponibilité 3 + 3 | 3 |
| 6 | GitOps ArgoCD | 3 |
| 7 | Réseau MetalLB | 2 |
| 8 | Stockage Rook-Ceph | 4 |
| 9 | Secrets Vault + ESO | 3 |
| 10 | Supervision Prometheus/Grafana | 3 |
| 11 | Sauvegarde Velero | 2 |
| 12 | Logs + application de démonstration | 2 |
| 13 | Test de redéploiement complet | 2 |
| 14 | Upgrade 1.30 vers 1.31 | 2 |
| 15 | Documentation, RETEX, rendu | 3 |
| | **Total** | **39 j-h** |

Coût interne d'un jour-homme : **320 €** (hypothèse : salaire brut de 45 k€/an, charges patronales de 45 %, 205 jours travaillés).
**Investissement de R&D : 39 × 320 ≈ 12 500 €.**

> À faire pendant le projet : noter dans chaque carte Kanban le temps réellement passé, puis recalculer ce tableau pour la soutenance. L'écart entre estimé et réel est un bon sujet pour le RETEX.

### 4.2 Coût d'infrastructure d'un cluster

Le projet tourne sur l'OpenStack de l'école, gratuit pour nous. Pour fixer un prix réaliste, nous prenons comme référence le prix public d'un hébergeur OpenStack français (OVHcloud Public Cloud).

| Ressource | Gabarit de référence | Prix unitaire | Mensuel |
|---|---|---|---|
| 3 control planes | B3-8 (2 vCPU, 8 Go) | 0,0605 $/h | 132 $ |
| 3 workers | B3-16 (4 vCPU, 16 Go) | 0,1208 $/h | 265 $ |
| Disques Ceph 3 × 100 Go | Block storage Classic | ≈ 0,048 $/Go/mois | 14 $ |
| IP publiques, S3 de sauvegarde | Estimation | n/a | ≈ 15 $ |
| **Total** | | | **≈ 426 $ ≈ 385 €** |

Avec un engagement de 12 mois chez l'hébergeur, le coût descend à environ 340 €. Le prix de vente reste calculé sur le tarif sans engagement, par prudence.

### 4.3 Coût d'exploitation (maintenance)

| Tâche récurrente | Fréquence | j-h par mois (offre Pro) |
|---|---|---|
| Lecture des alertes, tri, petits incidents | Continue | 0,8 |
| Correctifs de sécurité (OS, images, charts Helm) | Mensuelle | 0,4 |
| Montée de version Kubernetes (≈ 2 j × 3 par an) | Par version mineure | 0,5 |
| Test de restauration Velero | Trimestrielle | 0,1 |
| Rapport mensuel, suivi client | Mensuelle | 0,2 |
| **Total** | | **2,0 j-h/mois ≈ 640 €** |

Détail des 12 jours de mise en service Kubenstein : déploiement depuis le dépôt (1 j), adaptation au client (2 j), migration des charges EKS (6 j : inventaire, portage des manifests, ELB vers MetalLB, EBS vers Ceph, IAM/IRSA vers Vault), recette (2 j), formation et passation (1 j).

### 4.4 Marge par offre

| Offre | Infra | Exploitation | Astreinte | **Coût OWS** | **Prix** | **Marge** |
|---|---|---|---|---|---|---|
| Essentiel | 385 € | 1 j = 320 € | n/a | 705 € | 990 € | 285 € (29 %) |
| Pro | 385 € | 2 j = 640 € | n/a | 1 025 € | 1 490 € | 465 € (31 %) |
| Premium | 385 € | 3 j = 960 € | 400 € | 1 745 € | 2 490 € | 745 € (30 %) |

Mise en service Kubenstein : 7 800 € de prix pour 12 × 320 = 3 840 € de coût, soit **3 960 € de marge**.

### 4.5 Retour sur investissement pour OWS

- Avec **Kubenstein seul** : 12 500 € de R&D, moins 3 960 € de marge de mise en service, laissent 8 540 € à couvrir. Divisés par 465 € de marge mensuelle, **la R&D est remboursée en environ 18 mois**.
- Avec **3 clients Pro** signés la première année, à 2 600 € de mise en service chacun pour les suivants : **environ 6 à 7 mois**.
- C'est l'argument « produit » : la R&D est payée une seule fois, donc chaque client de plus fait baisser le seuil de rentabilité.

---

## 5. Comparaison avec AWS EKS

### 5.1 Coût d'infrastructure EKS équivalent (région Paris, eu-west-3, à la demande)

| Ressource | Hypothèse | Calcul | Mensuel |
|---|---|---|---|
| Control plane EKS | Support standard | 0,10 $/h × 730 h | 73 $ |
| 3 workers | m6i.xlarge (4 vCPU, 16 Go) | 0,224 $/h × 730 h × 3 | 491 $ |
| Volumes EBS gp3 | 3 × (100 + 30) Go | ≈ 0,093 $/Go/mois | 36 $ |
| Network Load Balancer | 1 NLB + trafic | ≈ 0,025 $/h + LCU | ≈ 24 $ |
| NAT Gateway | 1 passerelle + 100 Go | 0,048 $/h + 0,048 $/Go | ≈ 40 $ |
| Trafic sortant | 500 Go | ≈ 0,09 $/Go | 45 $ |
| S3 pour Velero | 200 Go | ≈ 0,024 $/Go/mois | 5 $ |
| **Total** | | | **≈ 714 $ ≈ 640 €** |

Les 3 control planes OWS n'ont pas d'équivalent ici : AWS les fournit dans les 0,10 $/h.

**Point d'attention pour Kubenstein :** le bon de commande impose Kubernetes 1.30 puis 1.31. AWS ne garde une version en support standard que 14 mois. Au-delà, le **support étendu coûte 0,60 $/h au lieu de 0,10 $/h**, soit environ **330 € de plus par mois** pour un cluster resté sur une ancienne version. Chez OWS, la montée de version est incluse dans l'abonnement.

Un engagement de 1 ou 3 ans chez AWS (Savings Plans) baisse le prix des workers d'environ 25 à 40 %. Le client peut l'obtenir, mais il se lie alors à AWS.

### 5.2 Ce qu'EKS ne fait pas à la place du client

Sur EKS, le client doit encore installer et maintenir lui-même : le CNI et ses politiques réseau, l'Ingress ou le load balancer controller, le stockage, Prometheus et Grafana, Velero, la gestion des secrets, ArgoCD, les mises à jour des nœuds et des add-ons, la montée de version tous les 14 mois au plus. Nous estimons ce travail à **environ 4 jours par mois**, à **450 €** le jour pour un ingénieur interne du client (hypothèse : profil plus senior que le nôtre, chargé). Cela fait **≈ 1 800 € par mois**.

### 5.3 Coût total pour le client (TCO)

| | Mensuel | 3 ans |
|---|---|---|
| **EKS** : 640 € d'infrastructure + 4 j × 450 € d'exploitation | **≈ 2 440 €** | **≈ 87 800 €** |
| **OWS Pro** : 1 490 € + 0,5 j × 450 € de suivi interne | **≈ 1 715 €** | **≈ 69 500 €** (7 800 € de mise en service inclus) |
| Économie | ≈ 725 €/mois | **≈ 18 300 € (−21 %)** |

**Seuil de rentabilité :** 1 715 € = 640 € + 450 € × x, donc **x ≈ 2,4 jours par mois**. Si l'exploitation d'EKS prend moins de 2,4 jours par mois au client, EKS reste moins cher. Il faut le dire honnêtement en soutenance : c'est l'hypothèse la plus discutable du dossier.

---

## 6. Avantages et inconvénients

### 6.1 Avantages d'OWS Kube HA face à EKS

| Avantage | Pourquoi c'est important pour Kubenstein |
|---|---|
| Plateforme complète, exploitée | Stockage, supervision, sauvegarde, secrets et GitOps sont livrés et maintenus |
| Coût prévisible | Forfait mensuel, pas de facture variable (trafic, NAT, LCU, support étendu) |
| Pas d'enfermement | 100 % open source, cluster reconstructible ailleurs à partir du dépôt |
| Souveraineté des données | Hébergement en France, hors du champ du Cloud Act américain si l'hébergeur est européen |
| Reproductible | Un seul dépôt Git reconstruit tout, ce qui sert aussi de plan de reprise d'activité |
| Contrôle des versions | Le client choisit quand monter de version, sans surcoût de support étendu |
| Interlocuteur unique | Support humain d'une petite équipe qui connaît le cluster |

### 6.2 Inconvénients et limites (à assumer)

| Inconvénient | Réponse d'OWS |
|---|---|
| Infrastructure brute plus chère qu'EKS seul | La valeur est dans l'exploitation incluse (voir le seuil en 5.3) |
| Pas d'élasticité instantanée (pas d'autoscaling de nœuds) | Ajout de worker sous 1 jour ouvré ; autoscaler OpenStack en feuille de route |
| Moins de services managés autour (RDS, SQS, IAM…) | Les bases de données restent hébergées dans le cluster ou chez un tiers |
| Une seule région, un seul site | Option Premium avec sauvegarde hors site et reprise testée |
| SLA 99,9 % contre 99,95 % chez EKS | Premium à 99,95 % ; un control plane HA à 3 nœuds tolère la perte d'un nœud |
| Petite équipe (2 personnes) : dépendance aux personnes | Tout est documenté et versionné, procédures écrites, pas de savoir caché |
| Ceph est exigeant à exploiter | Rook gère le cycle de vie ; alertes dédiées dans Grafana |

---

## 7. Risques

| Risque | Probabilité | Impact | Mesure |
|---|---|---|---|
| Panne matérielle d'un hôte OpenStack | Moyenne | Moyen | 3 CP, réplication Ceph × 3, règles d'anti-affinité entre VM |
| Perte de données | Faible | Fort | Velero vers un S3 hors cluster, restauration testée |
| Montée de version qui casse une application | Moyenne | Moyen | Procédure documentée, test sur un cluster de préproduction redéployé depuis Git |
| Fuite de secret | Faible | Fort | Vault + External Secrets, rien dans Git, rotation |
| Quotas ou droits OpenStack insuffisants (allowed-address-pairs) | Moyenne | Fort | Audit avant déploiement, alternative Octavia pour l'IP virtuelle |
| Sous-estimation du temps d'exploitation | Moyenne | Moyen | Suivi du temps réel dans le Kanban, révision annuelle des prix |
| Départ d'un des deux ingénieurs | Moyenne | Fort | Documentation complète, procédure de redéploiement chronométrée |
| Migration EKS plus longue que prévu | Moyenne | Moyen | Inventaire des dépendances AWS dès le premier jour, migration application par application |

---

## 8. Sources et hypothèses

**Prix publics relevés le 27/11/2026**
- Amazon EKS : 0,10 $/h par cluster en support standard, 0,60 $/h en support étendu. https://aws.amazon.com/eks/pricing/
- EC2 m6i.xlarge, eu-west-3, à la demande : 0,224 $/h ; m6i.large : 0,112 $/h. https://www.doit.com/compute/spot/eu-west-3/m6i.xlarge (agrégateur, à recouper avec la page EC2 d'AWS)
- OVHcloud Public Cloud : B3-8 à 0,0605 $/h, B3-16 à 0,1208 $/h ; control plane Managed Kubernetes gratuit en offre Free. https://www.ovhcloud.com/en/public-cloud/prices/

**Valeurs de mémoire, à vérifier sur la calculatrice AWS avant la soutenance** (https://calculator.aws/)
- EBS gp3 Paris ≈ 0,093 $/Go/mois ; NLB ≈ 0,025 $/h ; NAT Gateway 0,048 $/h et 0,048 $/Go ; trafic sortant ≈ 0,09 $/Go ; S3 Standard ≈ 0,024 $/Go/mois ; stockage bloc OVH Classic ≈ 0,048 $/Go/mois.

**Hypothèses OWS**
- Taux de change 1 $ = 0,90 €.
- Coût interne de 320 € par jour-homme ; coût interne client de 450 € par jour ; taux de vente de 650 € par jour.
- 4 jours par mois pour exploiter un EKS équipé comme le cluster OWS ; 0,5 jour par mois de suivi chez le client avec OWS.
- Trafic : 500 Go sortants par mois ; sauvegardes : 200 Go.
