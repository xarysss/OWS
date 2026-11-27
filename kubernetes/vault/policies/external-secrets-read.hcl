# Lecture seule des secrets de la plateforme OWS, utilisée par External Secrets.
path "secret/data/ows/*" {
  capabilities = ["read"]
}
path "secret/metadata/ows/*" {
  capabilities = ["read", "list"]
}
