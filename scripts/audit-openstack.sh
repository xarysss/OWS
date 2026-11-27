#!/usr/bin/env bash
# Audit du projet OpenStack avant le déploiement du cluster (ticket #3).
#
# Lit l'état du projet (quotas, gabarits, images, réseaux, IP flottantes, stockage,
# allowed-address-pairs) et le compare au dimensionnement d'openstack/tofu.
# Produit un rapport Markdown ; code de sortie 1 si un point bloque le déploiement.
#
#   export OS_CLOUD=ows            # ou : source /etc/kolla/admin-openrc.sh
#   scripts/audit-openstack.sh -o docs/audit-openstack.md
#
# Options d'environnement :
#   CP_COUNT=3 WORKER_COUNT=3            taille visée (défaut : HA 3 + 3)
#   CP_VCPU=3 CP_RAM_GB=8                gabarit control plane visé
#   WORKER_VCPU=4 WORKER_RAM_GB=12       gabarit worker minimum (12-16 Go)
#   ADMIN_OPENRC=/etc/kolla/admin-openrc.sh  lit en admin ce que le projet ne voit pas
#                                        (IP libres du réseau externe, pools Cinder, hyperviseurs)
#   BOOT_GB=40 CEPH_GB=100               disque système et volume Ceph par worker
#   FIP_NEEDED=5                         API + bastion + ArgoCD/Grafana/Vault
#   FLAVOR_CP=ows.cp FLAVOR_WORKER=ows.worker IMAGE_NAME=ubuntu-24.04 EXT_NET=public
#   LIVE_TEST=1                          crée puis supprime ows-audit-* pour tester
#                                        allowed-address-pairs (0 pour lecture seule)
set -Eeuo pipefail

OUT=""
while getopts "o:h" opt; do
  case $opt in
    o) OUT=$OPTARG ;;
    *) sed -n '2,21p' "$0"; exit 0 ;;
  esac
done

export CP_COUNT=${CP_COUNT:-3} WORKER_COUNT=${WORKER_COUNT:-3}
export CP_VCPU=${CP_VCPU:-3} CP_RAM_GB=${CP_RAM_GB:-8}
export WORKER_VCPU=${WORKER_VCPU:-4} WORKER_RAM_GB=${WORKER_RAM_GB:-12}
export BOOT_GB=${BOOT_GB:-40} CEPH_GB=${CEPH_GB:-100} FIP_NEEDED=${FIP_NEEDED:-5}
export FLAVOR_CP=${FLAVOR_CP:-ows.cp} FLAVOR_WORKER=${FLAVOR_WORKER:-ows.worker}
export IMAGE_NAME=${IMAGE_NAME:-ubuntu-24.04} EXT_NET=${EXT_NET:-public}
LIVE_TEST=${LIVE_TEST:-1}

command -v openstack >/dev/null || { echo "openstack (python-openstackclient) introuvable" >&2; exit 2; }
command -v python3   >/dev/null || { echo "python3 introuvable" >&2; exit 2; }

D=$(mktemp -d); export D
trap 'rm -rf "$D"' EXIT

# get <fichier> <commande openstack…> : JSON dans $D/<fichier>.json, erreur dans .err
get() {
  local f=$1; shift
  openstack "$@" -f json >"$D/$f.json" 2>"$D/$f.err" || echo "null" >"$D/$f.json"
}
# get_admin : idem avec les droits admin si ADMIN_OPENRC est fourni
get_admin() {
  if [[ -n ${ADMIN_OPENRC:-} ]]; then
    ( unset OS_CLOUD; set +u; source "$ADMIN_OPENRC"; get "$@" )
  else
    get "$@"
  fi
}

echo "Audit en cours (OS_CLOUD=${OS_CLOUD:-<openrc>})…" >&2
get token        token issue
get catalog      catalog list
get quota        quota show --usage
[[ $(cat "$D/quota.json") == null ]] && get quota quota show
get limits       limits show --absolute
get flavors      flavor list --all --long
get images       image list --long
get extnets      network list --external --long
get subnets      subnet list --long
get fips         floating ip list --long
get routers      router list --long
get networks     network list --long
get secgroups    security group list
get keypairs     keypair list
get extensions   extension list --network
get voltypes     volume type list --long
get volumes      volume list --long
get_admin volservices  volume service list
get_admin pools        volume backend pool list --long
get_admin hypervisors  --os-compute-api-version 2.87 hypervisor list --long
get_admin computesvc   compute service list
get_admin netagents    network agent list

# Disponibilité des IP du réseau externe (souvent réservé à l'admin)
EXT_ID=$(openstack network show "$EXT_NET" -f value -c id 2>/dev/null || true)
if [[ -n $EXT_ID ]]; then
  get_admin ipavail ip availability show "$EXT_ID"
else
  echo null >"$D/ipavail.json"
fi

# Test réel des allowed-address-pairs (ressources temporaires ows-audit-*)
echo "null" >"$D/aap.json"
if [[ $LIVE_TEST == 1 ]]; then
  cleanup_live() {
    openstack port delete ows-audit-port >/dev/null 2>&1 || true
    openstack subnet delete ows-audit-subnet >/dev/null 2>&1 || true
    openstack network delete ows-audit-net >/dev/null 2>&1 || true
  }
  cleanup_live
  {
    openstack network create ows-audit-net -f value -c id &&
    openstack subnet create ows-audit-subnet --network ows-audit-net \
      --subnet-range 10.99.0.0/24 --gateway none -f value -c id &&
    openstack port create ows-audit-port --network ows-audit-net \
      --allowed-address ip-address=10.99.0.192/27 -f json >"$D/aap.json"
  } >"$D/aap.log" 2>&1 || echo "null" >"$D/aap.json"
  cleanup_live
  # Vérifie qu'il ne reste rien
  openstack network show ows-audit-net >/dev/null 2>&1 && echo "reste" >"$D/aap.leftover" || true
fi

REPORT=$(python3 - <<'PY'
import json, os, re, datetime, pathlib
D = pathlib.Path(os.environ["D"]); E = os.environ

def load(n):
    try:
        return json.loads((D / f"{n}.json").read_text() or "null")
    except Exception:
        return None
def err(n):
    p = D / f"{n}.err"
    t = p.read_text().strip().splitlines() if p.exists() else []
    return t[-1][:160] if t else "commande refusée, sans message"
def g(d, *keys, default=None):
    for k in keys:
        if isinstance(d, dict) and k in d:
            return d[k]
    return default
def i(v, s=None):
    try:
        return int(v)
    except Exception:
        return s

cp, wk = i(E["CP_COUNT"]), i(E["WORKER_COUNT"])
cpv, cpr, wv, wr = i(E["CP_VCPU"]), i(E["CP_RAM_GB"]), i(E["WORKER_VCPU"]), i(E["WORKER_RAM_GB"])
min_cp, min_wk = (cpv, cpr), (wv, wr)
# Le besoin se calcule sur les gabarits réels quand ils existent (sinon sur les minimums)
for f in (load("flavors") or []):
    n, v, r = g(f, "Name", "name"), i(g(f, "VCPUs", "vcpus"), 0), i(g(f, "RAM", "ram"), 0) // 1024
    if n == E["FLAVOR_CP"]: cpv, cpr = max(v, cpv), max(r, cpr)
    if n == E["FLAVOR_WORKER"]: wv, wr = max(v, wv), max(r, wr)
boot, ceph, fipn = i(E["BOOT_GB"]), i(E["CEPH_GB"]), i(E["FIP_NEEDED"])
lb = 3  # ports MetalLB exposés (argocd, grafana, vault)

need = {
    "instances": cp + wk,
    "cores": cp * cpv + wk * wv,
    "ram": (cp * cpr + wk * wr) * 1024,
    "volumes": cp + wk + wk,
    "gigabytes": (cp + wk) * boot + wk * ceph,
    "floating-ips": fipn,
    "networks": 1, "subnets": 1, "routers": 1,
    "ports": cp + wk + 1 + lb + 2,          # nœuds, VIP, MetalLB, interface routeur + DHCP
    "secgroups": 3,                          # default + ows-k8s + ows-ingress
    "secgroup-rules": 16,
    "key-pairs": 1,
}
alias = {
    "floating-ips": ["floating-ips", "floating_ips", "floatingip"],
    "secgroups": ["secgroups", "security_groups", "security_group"],
    "secgroup-rules": ["secgroup-rules", "security_group_rules", "security_group_rule"],
    "key-pairs": ["key-pairs", "key_pairs"],
    "networks": ["networks", "network"], "subnets": ["subnets", "subnet"],
    "routers": ["routers", "router"], "ports": ["ports", "port"],
}

verdicts = []  # (sujet, état, détail)
def verdict(s, ok, d):
    verdicts.append((s, ok, d))

out = []
w = out.append
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
tok = load("token")
w(f"# Audit du projet OpenStack ({now})\n")
w(f"Généré par `scripts/audit-openstack.sh` (ticket #3). Cible : **{cp} control plane + {wk} workers**, "
  f"CP {cpv} vCPU / {cpr} Go, worker {wv} vCPU / {wr} Go, disque système {boot} Go, "
  f"volume Ceph {ceph} Go par worker, {fipn} IP flottantes.\n")
if not tok:
    w(f"**Authentification impossible** : `{err('token')}`\n")
    verdict("Authentification", False, err("token"))
else:
    w(f"Projet : `{g(tok, 'project_id')}`, utilisateur : `{g(tok, 'user_id')}`.\n")
hdr = len(out)  # la synthèse s'insère ici

# ---------- Services ----------
cat = load("catalog") or []
types = {g(c, "Type", "type") for c in cat}
w("## Services\n")
vol = "block-storage" if "block-storage" in types else "volumev3"
for t in ["identity", "compute", "network", "image", vol, "placement", "load-balancer"]:
    w(f"- `{t}` : {'présent' if t in types else 'absent'}")
w("")
miss = [t for t in ["compute", "network", "image", vol] if t not in types]
verdict("Services Nova/Neutron/Glance/Cinder", not miss and bool(cat), "manque " + ", ".join(miss) if miss else "OK")

# ---------- Quotas ----------
w("## Quotas\n")
q = load("quota")
rows = {}
if isinstance(q, list):
    for r in q:
        name = str(g(r, "Resource", "resource", default="")).lower()
        rows[name] = (i(g(r, "Limit", "limit")), i(g(r, "In Use", "in_use"), 0), i(g(r, "Reserved", "reserved"), 0))
elif isinstance(q, dict):
    for k, v in q.items():
        if isinstance(v, dict):
            rows[k.lower()] = (i(g(v, "limit")), i(g(v, "in_use"), 0), i(g(v, "reserved"), 0))
        else:
            rows[k.lower()] = (i(v), None, 0)
w("État : le quota total doit couvrir le besoin du cluster ; « utilisé » inclut les ressources `ows-*` déjà créées.\n")
w("| Ressource | Quota | Utilisé | Libre | Besoin | État |")
w("|---|---|---|---|---|---|")
quota_ko = []
for res, n in need.items():
    found = None
    for k in alias.get(res, [res]):
        if k in rows:
            found = rows[k]; break
    if not found:
        w(f"| {res} | ? | ? | ? | {n} | à vérifier |"); continue
    lim, used, resv = found
    if lim is None:
        w(f"| {res} | ? | {used} | ? | {n} | à vérifier |"); continue
    if lim < 0:
        w(f"| {res} | illimité | {used if used is not None else '?'} | illimité | {n} | OK |"); continue
    free = lim - (used or 0) - (resv or 0)
    ok = lim >= n  # le quota total couvre le cluster (ses propres ressources comptent dans « utilisé »)
    if not ok: quota_ko.append(res)
    unit = " Mo" if res == "ram" else (" Go" if res == "gigabytes" else "")
    w(f"| {res} | {lim}{unit} | {used if used is not None else '?'}{unit} | {free}{unit} | {n}{unit} | {'OK' if ok else '**insuffisant**'} |")
w("")
verdict("Quotas", bool(rows) and not quota_ko,
        ("insuffisants : " + ", ".join(quota_ko)) if quota_ko else ("OK" if rows else "illisibles : " + err("quota")))

# ---------- Gabarits ----------
w("## Gabarits (flavors)\n")
fl = load("flavors") or []
def fv(f): return i(g(f, "VCPUs", "vcpus"), 0)
def fr(f): return i(g(f, "RAM", "ram"), 0)
def fd(f): return i(g(f, "Disk", "disk"), 0)
w("| Nom | vCPU | RAM | Disque | Public |")
w("|---|---|---|---|---|")
for f in sorted(fl, key=lambda f: (fv(f), fr(f))):
    w(f"| {g(f, 'Name', 'name')} | {fv(f)} | {fr(f)//1024} Go | {fd(f)} Go | {g(f, 'Is Public', 'is_public', 'os-flavor-access:is_public')} |")
w("")
for role, name, (v, r) in [("control plane", E["FLAVOR_CP"], min_cp), ("worker", E["FLAVOR_WORKER"], min_wk)]:
    exact = [f for f in fl if g(f, "Name", "name") == name]
    if exact:
        f = exact[0]; ok = fv(f) >= v and fr(f) >= r * 1024
        verdict(f"Gabarit {role} `{name}`", ok, f"{fv(f)} vCPU / {fr(f)//1024} Go")
    else:
        cand = sorted([f for f in fl if fv(f) >= v and fr(f) >= r * 1024], key=lambda f: (fv(f), fr(f)))
        alt = g(cand[0], "Name", "name") if cand else None
        verdict(f"Gabarit {role} `{name}`", None,
                f"absent ; à créer ({v} vCPU / {r} Go, disque 0)" + (f" ou utiliser `{alt}`" if alt else ""))

# ---------- Images ----------
w("## Images\n")
im = load("images") or []
w("| Nom | Statut | Format | Visibilité | Taille |")
w("|---|---|---|---|---|")
for x in im:
    sz = i(g(x, "Size", "size"), 0)
    w(f"| {g(x, 'Name', 'name')} | {g(x, 'Status', 'status')} | {g(x, 'Disk Format', 'disk_format')} | "
      f"{g(x, 'Visibility', 'visibility')} | {sz // 2**20} Mo |")
w("")
want = [x for x in im if g(x, "Name", "name") == E["IMAGE_NAME"]]
noble = [x for x in im if re.search(r"(24\.04|noble)", str(g(x, "Name", "name")), re.I)]
if want:
    verdict(f"Image `{E['IMAGE_NAME']}`", g(want[0], "Status", "status") == "active", g(want[0], "Status", "status"))
else:
    verdict(f"Image `{E['IMAGE_NAME']}`", None,
            ("absente ; utiliser `" + g(noble[0], "Name", "name") + "`") if noble
            else "absente ; téléverser noble-server-cloudimg-amd64.img")

# ---------- Réseaux ----------
w("## Réseaux\n")
ext = load("extnets") or []
subs = load("subnets") or []
w("Réseaux externes :\n")
for n in ext:
    nid = g(n, "ID", "id")
    w(f"- `{g(n, 'Name', 'name')}` ({nid})")
    for s in subs:
        if g(s, "Network", "network_id") == nid:
            w(f"  - sous-réseau `{g(s, 'Name', 'name')}` {g(s, 'Subnet', 'cidr')}, "
              f"pools {g(s, 'Allocation Pools', 'allocation_pools')}")
if not ext:
    w(f"- aucun visible ({err('extnets') or 'liste vide'})")
w("")
names = [g(n, "Name", "name") for n in ext]
verdict(f"Réseau externe `{E['EXT_NET']}`", True if E["EXT_NET"] in names else None,
        "présent" if E["EXT_NET"] in names else ("absent ; choisir parmi " + ", ".join(map(str, names)) if names else "aucun réseau externe"))

nets = load("networks") or []
own = [g(n, "Name", "name") for n in nets if str(g(n, "Name", "name", default="")).startswith("ows-")]
w(f"Réseaux `ows-*` déjà présents : {', '.join(own) if own else 'aucun'}.\n")
k8s = [s for s in subs if str(g(s, "Subnet", "cidr")).startswith("10.20.0.")
       and not str(g(s, "Name", "name", default="")).startswith("ows-")]  # ows-* = le cluster lui-même
if k8s:
    verdict("Plage 10.20.0.0/24 libre", None, f"déjà utilisée par {g(k8s[0], 'Name', 'name')}")

# ---------- IP flottantes ----------
w("## IP flottantes\n")
fips = load("fips") or []
w(f"IP flottantes allouées au projet : {len(fips)}.\n")
for f in fips:
    w(f"- {g(f, 'Floating IP Address', 'floating_ip_address')} → {g(f, 'Fixed IP Address', 'fixed_ip_address') or 'libre'}")
ia = load("ipavail")
free_ext = None
if isinstance(ia, dict):
    tot, used = i(g(ia, "total_ips")), i(g(ia, "used_ips"))
    per = g(ia, "subnet_ip_availability") or []
    if tot is not None and used is not None:
        free_ext = tot - used
    w(f"\nDisponibilité du réseau externe : {used} utilisées sur {tot}, **{free_ext} libres**.")
    for s in per if isinstance(per, list) else []:
        w(f"- {g(s, 'subnet_name')} {g(s, 'cidr')} : {g(s, 'used_ips')}/{g(s, 'total_ips')}")
else:
    w(f"\nDisponibilité du réseau externe non lisible (droits admin requis) : `{err('ipavail')}`.")
w("")
unused = len([f for f in fips if not g(f, "Fixed IP Address", "fixed_ip_address")])
if free_ext is not None:
    verdict("IP flottantes libres", free_ext + unused >= fipn, f"{free_ext} libres sur le réseau + {unused} non associées, besoin {fipn}")
else:
    verdict("IP flottantes libres", None, f"pool non lisible ; {unused} déjà allouées non associées, besoin {fipn}")

# ---------- allowed-address-pairs ----------
w("## allowed-address-pairs et sécurité des ports\n")
exts = load("extensions") or []
aliases = {g(x, "Alias", "alias") for x in exts}
for a in ["allowed-address-pairs", "port-security", "router", "extraroute", "dns-integration", "standard-attr-tag"]:
    w(f"- extension `{a}` : {'oui' if a in aliases else 'non'}")
aap = load("aap")
live = os.path.exists(D / "aap.log")
if isinstance(aap, dict):
    pairs = g(aap, "allowed_address_pairs") or []
    w(f"\nTest réel : port `ows-audit-port` créé avec la paire {pairs}, puis supprimé.")
    verdict("allowed-address-pairs", bool(pairs), "création d'un port avec paire acceptée")
elif live:
    log = (D / "aap.log").read_text().strip().splitlines()
    w(f"\nTest réel en échec : `{log[-1][:200] if log else '?'}`")
    verdict("allowed-address-pairs", False, "refusé : VIP kube-vip et MetalLB impossibles sans paire autorisée")
else:
    verdict("allowed-address-pairs", True if "allowed-address-pairs" in aliases else None,
            "extension présente (test réel désactivé)" if "allowed-address-pairs" in aliases else "à tester")
if (D / "aap.leftover").exists():
    w("\n**Attention** : `ows-audit-net` n'a pas pu être supprimé, à retirer à la main.")
w("")

# ---------- Stockage ----------
w("## Stockage (Cinder)\n")
vt = load("voltypes") or []
w("Types de volume : " + (", ".join(f"`{g(v, 'Name', 'name')}`" for v in vt) or "aucun visible") + ".\n")
vs = load("volservices")
if isinstance(vs, list):
    for s in vs:
        w(f"- service `{g(s, 'Binary', 'binary')}` sur {g(s, 'Host', 'host')} : {g(s, 'State', 'state')} / {g(s, 'Status', 'status')}")
pools = load("pools")
cap = None
if isinstance(pools, list) and pools:
    for p in pools:
        c = g(p, "Capabilities", "capabilities") or p
        tot = g(c, "Total Capacity", "total_capacity_gb"); fr_ = g(c, "Free Capacity", "free_capacity_gb")
        w(f"- pool `{g(p, 'Name', 'name')}` : {fr_} Go libres sur {tot} Go")
        try: cap = (cap or 0) + float(fr_)
        except Exception: pass
else:
    w(f"- capacité des pools non lisible (admin requis) : `{err('pools')}`")
vols = load("volumes") or []
w(f"\nVolumes existants dans le projet : {len(vols)}.\n")
upv = [s for s in (vs or []) if g(s, "Binary", "binary") == "cinder-volume" and g(s, "State", "state") == "up"] if isinstance(vs, list) else []
if cap is not None:
    verdict("Capacité Cinder", cap >= need["gigabytes"], f"{cap:.0f} Go libres, besoin {need['gigabytes']} Go")
elif isinstance(vs, list):
    verdict("Service cinder-volume", bool(upv), "up" if upv else "aucun cinder-volume up")
else:
    verdict("Stockage", None, "capacité à confirmer par l'admin")

# ---------- Capacité physique (admin) ----------
w("## Hyperviseurs (admin)\n")
hv = load("hypervisors")
if isinstance(hv, list) and hv:
    w("| Hôte | État | vCPU utilisés / total | RAM utilisée / totale |")
    w("|---|---|---|---|")
    for h in hv:
        w(f"| {g(h, 'Hypervisor Hostname', 'name')} | {g(h, 'State', 'state')} | "
          f"{g(h, 'vCPUs Used', 'vcpus_used', default='?')} / {g(h, 'vCPUs', 'vcpus', default='?')} | "
          f"{g(h, 'Memory MB Used', 'memory_mb_used', default='?')} / {g(h, 'Memory MB', 'memory_mb', default='?')} Mo |")
    try:
        fram = sum(i(g(h, "Memory MB", "memory_mb"), 0) - i(g(h, "Memory MB Used", "memory_mb_used"), 0) for h in hv)
        fcpu = sum(i(g(h, "vCPUs", "vcpus"), 0) * 4 - i(g(h, "vCPUs Used", "vcpus_used"), 0) for h in hv)
        verdict("Capacité physique", fram >= need["ram"] and fcpu >= need["cores"],
                f"{fram // 1024} Go de RAM libres (besoin {need['ram'] // 1024}), {fcpu} vCPU placables à 4:1 (besoin {need['cores']})")
    except Exception:
        pass
    w("\nNova applique ses ratios d'allocation (vCPU 4:1 et RAM 1:1 par défaut depuis 2023.1) via Placement.")
else:
    w(f"Non lisible avec ces droits : `{err('hypervisors')}`.")
w("")
for name, key in [("Services Nova", "computesvc"), ("Agents Neutron", "netagents")]:
    lst = load(key)
    if isinstance(lst, list) and lst:
        down = [g(s, "Binary", "binary", "Agent Type") for s in lst if str(g(s, "State", "state", "Alive", default="up")).lower() in ("down", "false", "xxx")]
        verdict(name, not down, ("en panne : " + ", ".join(map(str, down))) if down else f"{len(lst)} actifs")
    elif isinstance(lst, list):
        w(f"- {name} : liste vide avec ces droits (lancer avec ADMIN_OPENRC).")

# ---------- Synthèse ----------
lab = {True: "OK", False: "**BLOQUANT**", None: "à faire"}
head = ["## Synthèse\n", "| Point | État | Détail |", "|---|---|---|"]
head += [f"| {s} | {lab[ok]} | {d} |" for s, ok, d in verdicts]
ko = [s for s, ok, _ in verdicts if ok is False]
todo = [s for s, ok, _ in verdicts if ok is None]
concl = ("\n**Dimensionnement validé contre les quotas.**" if not ko and not todo else
         "\n**Dimensionnement validé** sous réserve des actions « à faire »." if not ko else
         "\n**Dimensionnement non validé** : " + ", ".join(ko) + ".")
print("\n".join(out[:hdr] + head + [concl, ""] + out[hdr:]))
print("__KO__" if ko else "__OK__")
PY
)

STATUS=$(tail -n1 <<<"$REPORT")
REPORT=$(sed '$d' <<<"$REPORT")
if [[ -n $OUT ]]; then
  printf '%s\n' "$REPORT" >"$OUT"
  echo "Rapport écrit dans $OUT" >&2
else
  printf '%s\n' "$REPORT"
fi
[[ $STATUS == __OK__ ]]
