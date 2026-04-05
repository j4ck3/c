#!/usr/bin/env python3
"""Generate ov.conf from varlock-resolved env vars and start OpenViking server."""
import json
import os
import sys

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    print("FATAL: OPENAI_API_KEY not set (should be resolved by varlock from Bitwarden)", file=sys.stderr)
    sys.exit(1)

api_base = os.environ.get("OPENAI_API_BASE", "https://api.openai.com/v1")
embedding_model = os.environ.get("OPENVIKING_EMBEDDING_MODEL", "text-embedding-3-large")
embedding_dim = int(os.environ.get("OPENVIKING_EMBEDDING_DIM", "3072"))
vlm_model = os.environ.get("OPENVIKING_VLM_MODEL", "gpt-4o")
max_embedding_concurrent = int(os.environ.get("OPENVIKING_EMBEDDING_CONCURRENCY", "10"))
max_vlm_concurrent = int(os.environ.get("OPENVIKING_VLM_CONCURRENCY", "100"))

root_api_key = os.environ.get("OPENVIKING_API_KEY", "ov-internal-docker-key")

config = {
    "storage": {"workspace": "/app/data"},
    "server": {"host": "0.0.0.0", "port": 1933, "root_api_key": root_api_key},
    "log": {"level": os.environ.get("OPENVIKING_LOG_LEVEL", "INFO"), "output": "stdout"},
    "embedding": {
        "dense": {
            "api_base": api_base,
            "api_key": OPENAI_API_KEY,
            "provider": "openai",
            "dimension": embedding_dim,
            "model": embedding_model,
        },
        "max_concurrent": max_embedding_concurrent,
    },
    "vlm": {
        "api_base": api_base,
        "api_key": OPENAI_API_KEY,
        "provider": "openai",
        "model": vlm_model,
        "max_concurrent": max_vlm_concurrent,
    },
}

conf_path = "/app/ov.conf"
with open(conf_path, "w") as f:
    json.dump(config, f, indent=2)

os.environ["OPENVIKING_CONFIG_FILE"] = conf_path
os.chdir("/app")
os.execvp("openviking-server", ["openviking-server"])
