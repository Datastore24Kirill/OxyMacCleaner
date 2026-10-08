import Foundation

public enum UpdateInstaller {
  public static let script = #"""
  set -eu
  old_pid="$1"; app="$2"; next="$3"; stage="$4"
  /bin/mkdir -p "$stage/rollback"
  backup="$stage/rollback/OxyMac Cleaner.app"
  n=0
  while kill -0 "$old_pid" 2>/dev/null; do
    n=$((n+1)); [ "$n" -lt 60 ] || exit 1
    sleep 1
  done
  /bin/mv "$app" "$backup"
  if ! /bin/mv "$next" "$app"; then /bin/mv "$backup" "$app"; /usr/bin/open "$app"; exit 1; fi
  "$app/Contents/MacOS/OxyMacCleaner" --oxy-update-health "$stage/healthy" &
  child=$!
  n=0
  while [ "$n" -lt 45 ]; do
    if [ -f "$stage/healthy" ]; then echo 'Update launched successfully; rollback copy retained'; exit 0; fi
    if ! kill -0 "$child" 2>/dev/null; then break; fi
    n=$((n+1)); sleep 1
  done
  if [ -f "$stage/healthy" ]; then echo 'Update launched successfully; rollback copy retained'; exit 0; fi
  echo 'No launch confirmation; restoring previous version'
  kill -TERM "$child" 2>/dev/null || true
  sleep 2
  if kill -0 "$child" 2>/dev/null; then echo 'New app still running; manual recovery required. Backup retained.'; exit 1; fi
  /bin/mv "$app" "$stage/failed-update"
  /bin/mv "$backup" "$app"
  /usr/bin/open "$app"
  """#
}
