# 手元で検証するときの環境。使い方: source scripts/dev-env.sh
# .tools/（Terraform、uv、Python）と .venv/（Checkov、PyYAML）を使う。どちらも git の管理外。

_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="$_repo/.tools/bin:$_repo/.venv/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$_repo/.tools/tf-plugin-cache"
export UV_CACHE_DIR="$_repo/.tools/uv-cache"
export UV_PYTHON_INSTALL_DIR="$_repo/.tools/python"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

unset _repo
