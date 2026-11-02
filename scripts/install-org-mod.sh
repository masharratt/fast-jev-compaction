#!/usr/bin/env bash
# Install fast-jev-compaction as an organization mod.
#
# Claude Code >= 2.1.299 skips a user-installed plugin's session.compact hook
# whenever managed settings exist (incl. claude.ai admin-console settings) or
# the login is a Team/Enterprise org. A mod only counts as the organization's
# when it is loaded in place from a local directory marketplace that managed
# settings name, and that directory is writable only by an administrator.
#
# Usage: sudo ./install-org-mod.sh [plugin-source-dir] [dest-root]
#   plugin-source-dir  default: the repository this script lives in
#   dest-root          default: /opt/claude-org-plugins
set -euo pipefail

SRC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEST="${2:-/opt/claude-org-plugins}"
MARKETPLACE="org-local"
PLUGIN="fast-jev-compaction"

if [[ $EUID -ne 0 ]]; then
  echo "error: run with sudo (the directory must be root-owned)" >&2
  exit 1
fi
for f in .claude-plugin/plugin.json hooks/hooks.json; do
  [[ -f "$SRC/$f" ]] || { echo "error: $SRC/$f missing; not a plugin dir" >&2; exit 2; }
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/.claude-plugin" "$STAGE/plugins/$PLUGIN"
# Runtime files only: no tests, media, node_modules or git metadata.
for item in .claude-plugin hooks src types package.json tsconfig.hooks.json LICENSE README.md; do
  [[ -e "$SRC/$item" ]] && cp -R "$SRC/$item" "$STAGE/plugins/$PLUGIN/"
done
# The plugin's own marketplace manifest would confuse the loader here.
rm -f "$STAGE/plugins/$PLUGIN/.claude-plugin/marketplace.json"
cat > "$STAGE/.claude-plugin/marketplace.json" <<EOF
{
  "name": "$MARKETPLACE",
  "owner": { "name": "organization" },
  "plugins": [ { "name": "$PLUGIN", "source": "./plugins/$PLUGIN" } ]
}
EOF

rm -rf "$DEST.new"
mv "$STAGE" "$DEST.new"
chown -R root:root "$DEST.new"
chmod -R u=rwX,go=rX "$DEST.new"
rm -rf "$DEST.old"
[[ -d "$DEST" ]] && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"
rm -rf "$DEST.old"
trap - EXIT

# Every parent must also be admin-only writable.
p="$DEST"
while [[ "$p" != "/" ]]; do
  if [[ -n "$(find "$p" -maxdepth 0 \( -perm -o+w -o -perm -g+w \) 2>/dev/null)" ]] || [[ "$(stat -c %u "$p")" != 0 ]]; then
    echo "warning: $p is not root-owned/admin-only; Claude Code may refuse the mod" >&2
  fi
  p="$(dirname "$p")"
done

echo "installed: $DEST/plugins/$PLUGIN"
echo
echo "Add these keys to managed settings (claude.ai admin console > Claude Code > managed settings):"
cat <<EOF
{
  "extraKnownMarketplaces": {
    "$MARKETPLACE": { "source": { "source": "directory", "path": "$DEST" } }
  },
  "enabledPlugins": { "$PLUGIN@$MARKETPLACE": true },
  "appendPlugins": ["$PLUGIN@$MARKETPLACE"]
}
EOF
