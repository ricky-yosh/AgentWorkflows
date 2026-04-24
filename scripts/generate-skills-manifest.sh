#!/usr/bin/env bash
# Generates skills-manifest.json from the Skill Bundle, copies SKILL.md files
# into the app bundle preserving their Skills/<name>/ directory structure, and
# asserts parity with PresenceChecker.requiredSkills. Run as a build-phase script.
set -euo pipefail

PRESENCE_CHECKER="${SRCROOT}/AgentWorkflows/Engine/PresenceChecker.swift"
SKILLS_DIR="${SRCROOT}/AgentWorkflows/Resources/Skills"
RESOURCES_OUT="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
MANIFEST_OUT="${RESOURCES_OUT}/skills-manifest.json"
SKILLS_OUT="${RESOURCES_OUT}/Skills"

# Parse requiredSkills from PresenceChecker.swift so that any Swift-side addition
# automatically breaks the build if the bundle is not updated to match.
REQUIRED_SKILLS=()
while IFS= read -r skill; do
    REQUIRED_SKILLS+=("${skill}")
done < <(
    awk '/static let requiredSkills: \[String\] = \[/,/^    \]/' \
        "${PRESENCE_CHECKER}" \
    | grep -oE '"[^"]+"' | tr -d '"'
)

if [[ ${#REQUIRED_SKILLS[@]} -eq 0 ]]; then
    echo "error: Could not parse PresenceChecker.requiredSkills from ${PRESENCE_CHECKER}" >&2
    exit 1
fi

# Parity check: every required skill must have a SKILL.md in the bundle.
for skill in "${REQUIRED_SKILLS[@]}"; do
    if [[ ! -f "${SKILLS_DIR}/${skill}/SKILL.md" ]]; then
        echo "error: Skill Bundle is missing required skill '${skill}' — add AgentWorkflows/Resources/Skills/${skill}/SKILL.md" >&2
        exit 1
    fi
done

# Copy SKILL.md files into the bundle preserving Skills/<name>/ structure.
# (The synchronized group's membershipExceptions prevent Xcode from copying
# them flat; this script is the sole copy path for these files.)
for skill in "${REQUIRED_SKILLS[@]}"; do
    mkdir -p "${SKILLS_OUT}/${skill}"
    cp "${SKILLS_DIR}/${skill}/SKILL.md" "${SKILLS_OUT}/${skill}/SKILL.md"
done

# Generate manifest JSON.
{
    printf '['
    first=true
    for skill in "${REQUIRED_SKILLS[@]}"; do
        sha=$(shasum -a 256 "${SKILLS_DIR}/${skill}/SKILL.md" | cut -d' ' -f1)
        if [[ "${first}" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '\n  {"name":"%s","sha256":"%s","priorSha256s":[]}' "${skill}" "${sha}"
    done
    printf '\n]\n'
} > "${MANIFEST_OUT}"

echo "note: Generated $(basename "${MANIFEST_OUT}") with ${#REQUIRED_SKILLS[@]} entries"
