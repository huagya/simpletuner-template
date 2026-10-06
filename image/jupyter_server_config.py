# Jupyter has no token of its own. Caddy basic auth is the only login.
# The process still binds 127.0.0.1, so the port is not public by itself.
c.ServerApp.ip = "127.0.0.1"
c.ServerApp.port = 18888
c.ServerApp.root_dir = "/workspace"
c.ServerApp.preferred_dir = "/workspace"
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.token = ""
c.ServerApp.password = ""
c.IdentityProvider.token = ""
c.ServerApp.allow_origin = "*"
c.ServerApp.disable_check_xsrf = False
c.ServerApp.allow_remote_access = True
