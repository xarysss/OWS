# Administration courante (remplace le jeton root, à révoquer après le bootstrap).
path "secret/*"                 { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/policies/acl/*"       { capabilities = ["create", "read", "update", "delete", "list"] }
path "auth/kubernetes/role/*"   { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/storage/raft/*"       { capabilities = ["read", "list"] }
path "sys/health"               { capabilities = ["read"] }
