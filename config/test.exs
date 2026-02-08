import Config

# Test-specific configuration
config :logger, level: :warning

# Enable test mode for Git adapter (disables template dir to avoid hooks)
config :jido_vfs, test_mode: true
