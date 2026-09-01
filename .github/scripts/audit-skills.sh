#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SKILLS_LOCK_FILE="$ROOT_DIR/skills-lock.json"
AUDIT_FILE="$ROOT_DIR/skills-audit.json"

usage() {
  cat <<'EOF'
Usage:
  audit-skills.sh --write
  audit-skills.sh --verify

Generates a persistent audit report for skills tracked in skills-lock.json.
--verify regenerates the report, checks that the committed file is current, and
fails only if a critical audit is reported.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" >&2
}

list_locked_skills() {
  if [[ ! -f "$SKILLS_LOCK_FILE" ]]; then
    return 0
  fi

  node -e '
    const fs = require("fs");
    const filePath = process.argv[1];
    const payload = JSON.parse(fs.readFileSync(filePath, "utf8"));
    for (const skillName of Object.keys(payload.skills || {}).sort()) {
      const entry = payload.skills[skillName];
      if (entry?.source) {
        process.stdout.write(`${skillName}\t${entry.source}\n`);
      }
    }
  ' "$SKILLS_LOCK_FILE"
}

audit_skill_json() {
  local skill_name="$1"
  local source="$2"
  local temp_dir
  temp_dir=$(mktemp -d)
  local output_file="$temp_dir/skills-audit.txt"

  if ! (
    cd "$temp_dir"
    npx --yes skills add "$source" --skill "$skill_name" --agent github-copilot -y --copy
  ) < /dev/null >"$output_file" 2>&1; then
    cat "$output_file" >&2
    rm -rf "$temp_dir"
    fail "Audit install failed for $skill_name from $source"
  fi

  node -e '
    const fs = require("fs");
    const outputPath = process.argv[1];
    const skillName = process.argv[2];
    const source = process.argv[3];
    const text = fs.readFileSync(outputPath, "utf8");
    const lines = text
      .split(/\r?\n/)
      .map((line) => line.replace(/[│|]/g, "").trim())
      .filter(Boolean);

    let assessment = null;
    for (const line of lines) {
      if (!line.includes(skillName)) {
        continue;
      }

      const parts = line.split(/\s{2,}/).map((part) => part.trim()).filter(Boolean);
      if (parts.length >= 4 && parts[0] === skillName) {
        assessment = parts.slice(1, 4);
        break;
      }
    }

    const [gen = "Unavailable", socket = "Unavailable", snyk = "Unavailable"] = assessment || [];
    const critical = [gen, socket, snyk].some((value) => /critical/i.test(value));

    process.stdout.write(JSON.stringify({
      name: skillName,
      source,
      hasAssessment: Boolean(assessment),
      gen,
      socket,
      snyk,
      critical,
    }));
  ' "$output_file" "$skill_name" "$source"

  rm -rf "$temp_dir"
}

build_report() {
  local output_path="$1"
  local first_entry=true

  {
    printf '{\n'
    printf '  "version": 1,\n'
    printf '  "skills": [\n'

    while IFS=$'\t' read -r skill_name source; do
      [[ -n "$skill_name" ]] || continue
      local skill_json
      log "Auditing: $skill_name ($source)"
      skill_json=$(audit_skill_json "$skill_name" "$source")
      if [[ "$first_entry" == true ]]; then
        first_entry=false
      else
        printf ',\n'
      fi
      printf '    %s' "$skill_json"
    done < <(list_locked_skills)

    printf '\n  ]\n'
    printf '}\n'
  } >"$output_path"
}

report_has_critical() {
  local report_path="$1"

  node -e '
    const fs = require("fs");
    const reportPath = process.argv[1];
    const payload = JSON.parse(fs.readFileSync(reportPath, "utf8"));
    const criticalSkills = (payload.skills || []).filter((skill) => skill.critical);
    if (criticalSkills.length > 0) {
      for (const skill of criticalSkills) {
        console.error(`Critical audit: ${skill.name} (${skill.source})`);
      }
      process.exit(1);
    }
  ' "$report_path"
}

main() {
  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  local mode="$1"
  local temp_report
  temp_report=$(mktemp)
  trap "rm -f '$temp_report'" EXIT

  build_report "$temp_report"

  case "$mode" in
    --write)
      mv "$temp_report" "$AUDIT_FILE"
      trap - EXIT
      log "Wrote $(basename "$AUDIT_FILE")"
      ;;
    --verify)
      [[ -f "$AUDIT_FILE" ]] || fail "Missing audit file: $(basename "$AUDIT_FILE")"

      if ! cmp -s "$AUDIT_FILE" "$temp_report"; then
        fail "$(basename "$AUDIT_FILE") is out of date; regenerate it before pushing"
      fi

      report_has_critical "$temp_report"
      log "Audit verification completed successfully"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
