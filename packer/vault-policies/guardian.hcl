path "auth/okta/users/*" {
    capabilities = ["read", "create", "update"]
}

path "auth/token/lookup-accessor" {
    capabilities = ["read", "create", "update"]
}

path "auth/token/create/guardian-enduser" {
    capabilities = ["create", "update"]
}

path "identity/lookup/entity" {
    capabilities = ["create","update"]
}

path "keys/*" {
    capabilities = ["read", "create"]
}