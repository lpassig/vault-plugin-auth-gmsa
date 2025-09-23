plugin_directory = "/private/tmp/vault-plugins"

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

storage "inmem" {}

listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}

disable_mlock = true
log_level = "debug"

# Dev mode settings
ui = true
