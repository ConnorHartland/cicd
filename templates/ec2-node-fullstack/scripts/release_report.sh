#!/bin/bash
# release_report.sh
# Generates a consolidated security/quality report for releases
# Posts markdown summary to PR + saves JSON artifact
# Monorepo version: Scans both server (root) and client directories

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/report_utils.sh"

echo "=== Generating Release Security Report (Fullstack) ==="

# Extract version from branch name (release/X.X.X)
VERSION=${BITBUCKET_BRANCH#release/}
echo "Release Version: ${VERSION}"

# Get project info
PROJECT_KEY=$(get_project_key)
PROJECT_NAME=$(node -p "require('./package.json').name" 2>/dev/null || echo "Unknown Project")

#######################################
# RUN SCANS (Server + Client)
#######################################
run_npm_audit
extract_npm_details
echo "npm audit (combined) - Critical: ${NPM_CRITICAL}, High: ${NPM_HIGH}, Moderate: ${NPM_MODERATE}, Low: ${NPM_LOW}"

run_snyk_scan
extract_snyk_details
if [ -n "$SNYK_TOKEN" ]; then
  echo "Snyk (combined) - Critical: ${SNYK_CRITICAL}, High: ${SNYK_HIGH}, Medium: ${SNYK_MEDIUM}, Low: ${SNYK_LOW}"
else
  echo "SNYK_TOKEN not set - skipping Snyk scan"
fi

fetch_sonarqube "$PROJECT_KEY"
fetch_sonar_issues "$PROJECT_KEY"
echo "SonarQube - QG: ${SONAR_QG_STATUS}, Bugs: ${SONAR_BUGS}, Vulns: ${SONAR_VULNS}"

get_git_summary 15
COMMIT_COUNT=$(echo "$GIT_COMMITS" | grep -c "." || echo "0")
echo "Git - ${COMMIT_COUNT} commits in this release"

#######################################
# DETERMINE OVERALL STATUS
#######################################
OVERALL_STATUS="PASSED"
OVERALL_ICON=":white_check_mark:"

if [ "$SONAR_QG_STATUS" = "ERROR" ] || [ "$NPM_CRITICAL" -gt 0 ] || [ "$SNYK_CRITICAL" -gt 0 ]; then
  OVERALL_STATUS="FAILED"
  OVERALL_ICON=":x:"
elif [ "$NPM_HIGH" -gt 0 ] || [ "$SNYK_HIGH" -gt 0 ]; then
  OVERALL_STATUS="WARNINGS"
  OVERALL_ICON=":warning:"
fi

TIMESTAMP=$(get_timestamp)

#######################################
# BUILD MARKDOWN REPORT (PR Comment)
#######################################
echo ""
echo "Building markdown report..."

REPORT="## :package: Release Report - v${VERSION}\n\n"
REPORT+="**Project:** ${PROJECT_NAME} (Fullstack)\n"
REPORT+="**Branch:** ${BITBUCKET_BRANCH}\n"
REPORT+="**Commit:** ${BITBUCKET_COMMIT:0:7}\n"
REPORT+="**Overall Status:** ${OVERALL_ICON} ${OVERALL_STATUS}\n\n"
REPORT+="_Scanning server + client dependencies_\n\n"
REPORT+="---\n\n"

# SonarQube Section
REPORT+="### :mag: Code Quality (SonarQube)\n\n"
if [ "$SONAR_QG_STATUS" = "OK" ]; then
  REPORT+=":white_check_mark: **Quality Gate: PASSED**\n\n"
elif [ "$SONAR_QG_STATUS" = "ERROR" ]; then
  REPORT+=":x: **Quality Gate: FAILED**\n\n"
else
  REPORT+="**Quality Gate:** ${SONAR_QG_STATUS}\n\n"
fi

REPORT+="| Metric | Value |\n"
REPORT+="|--------|-------|\n"
REPORT+="| :bug: Bugs | ${SONAR_BUGS} |\n"
REPORT+="| :lock: Vulnerabilities | ${SONAR_VULNS} |\n"
REPORT+="| :poop: Code Smells | ${SONAR_SMELLS} |\n"
REPORT+="| :fire: Security Hotspots | ${SONAR_HOTSPOTS} |\n"
REPORT+="| :bar_chart: Coverage | ${SONAR_COVERAGE}% |\n\n"

# Show top 5 blocker/critical issues inline
if [ -n "$SONAR_DETAILS" ]; then
  SONAR_ISSUE_COUNT=$(echo "$SONAR_DETAILS" | grep -c "." || echo "0")
  SONAR_TOP5=$(echo "$SONAR_DETAILS" | head -5 | while IFS='|' read -r severity msg file; do
    echo "| ${severity} | ${msg} | ${file} |"
  done)
  REPORT+="\n**Blocker/Critical Issues:**\n\n"
  REPORT+="| Severity | Message | File |\n"
  REPORT+="|----------|---------|------|\n"
  REPORT+="${SONAR_TOP5}\n"
  if [ "$SONAR_ISSUE_COUNT" -gt 5 ]; then
    REPORT+="\n_...and $((SONAR_ISSUE_COUNT - 5)) more_\n"
  fi
  REPORT+="\n"
fi

if [ -n "$SONAR_HOST_URL" ]; then
  REPORT+="[View Full SonarQube Report](${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY})\n\n"
fi

# npm audit Section
REPORT+="---\n\n"
REPORT+="### :package: Dependency Audit (npm)\n\n"
REPORT+="_Combined results from server + client_\n\n"

if [ "$NPM_TOTAL" -eq 0 ]; then
  REPORT+=":white_check_mark: **No vulnerabilities found**\n\n"
else
  REPORT+="| Severity | Count |\n"
  REPORT+="|----------|-------|\n"
  REPORT+="| :octagonal_sign: Critical | ${NPM_CRITICAL} |\n"
  REPORT+="| :bangbang: High | ${NPM_HIGH} |\n"
  REPORT+="| :warning: Moderate | ${NPM_MODERATE} |\n"
  REPORT+="| :information_source: Low | ${NPM_LOW} |\n"
  REPORT+="| **Total** | **${NPM_TOTAL}** |\n\n"

  if [ -n "$NPM_DETAILS" ]; then
    NPM_DETAIL_COUNT=$((NPM_CRITICAL + NPM_HIGH))
    NPM_TOP5=$(echo -e "$NPM_DETAILS" | head -5 | while IFS='|' read -r severity pkg desc; do
      echo "| ${severity} | ${pkg} | ${desc} |"
    done)
    REPORT+="\n**Critical/High Vulnerabilities:**\n\n"
    REPORT+="| Severity | Package | Description |\n"
    REPORT+="|----------|---------|-------------|\n"
    REPORT+="${NPM_TOP5}\n"
    if [ "$NPM_DETAIL_COUNT" -gt 5 ]; then
      REPORT+="\n_...and $((NPM_DETAIL_COUNT - 5)) more_\n"
    fi
    REPORT+="\n"
  fi
fi

# Snyk Section
REPORT+="---\n\n"
REPORT+="### :shield: Security Scan (Snyk)\n\n"

if [ -z "$SNYK_TOKEN" ]; then
  REPORT+="_Snyk scan skipped (SNYK_TOKEN not configured)_\n\n"
elif [ "$SNYK_CRITICAL" -eq 0 ] && [ "$SNYK_HIGH" -eq 0 ] && [ "$SNYK_MEDIUM" -eq 0 ] && [ "$SNYK_LOW" -eq 0 ]; then
  REPORT+=":white_check_mark: **No vulnerabilities found**\n\n"
else
  REPORT+="_Combined results from server + client_\n\n"
  REPORT+="| Severity | Count |\n"
  REPORT+="|----------|-------|\n"
  REPORT+="| :octagonal_sign: Critical | ${SNYK_CRITICAL} |\n"
  REPORT+="| :bangbang: High | ${SNYK_HIGH} |\n"
  REPORT+="| :warning: Medium | ${SNYK_MEDIUM} |\n"
  REPORT+="| :information_source: Low | ${SNYK_LOW} |\n\n"

  if [ -n "$SNYK_DETAILS" ]; then
    SNYK_DETAIL_COUNT=$((SNYK_CRITICAL + SNYK_HIGH))
    SNYK_TOP5=$(echo -e "$SNYK_DETAILS" | head -5 | while IFS='|' read -r severity pkg desc; do
      echo "| ${severity} | ${pkg} | ${desc} |"
    done)
    REPORT+="\n**Critical/High Vulnerabilities:**\n\n"
    REPORT+="| Severity | Package | Description |\n"
    REPORT+="|----------|---------|-------------|\n"
    REPORT+="${SNYK_TOP5}\n"
    if [ "$SNYK_DETAIL_COUNT" -gt 5 ]; then
      REPORT+="\n_...and $((SNYK_DETAIL_COUNT - 5)) more_\n"
    fi
    REPORT+="\n"
  fi
fi

# Git Commits Section
if [ -n "$GIT_COMMITS" ]; then
  REPORT+="---\n\n"
  REPORT+="### :git: Changes in This Release\n\n"
  REPORT+="| Commit | Message | Author |\n"
  REPORT+="|--------|---------|--------|\n"
  COMMITS_TABLE=$(echo "$GIT_COMMITS" | head -10 | while IFS='|' read -r sha msg author; do
    # Truncate long messages
    msg_short="${msg:0:60}"
    [ ${#msg} -gt 60 ] && msg_short="${msg_short}..."
    echo "| \`${sha}\` | ${msg_short} | ${author} |"
  done)
  REPORT+="${COMMITS_TABLE}\n"
  if [ "$COMMIT_COUNT" -gt 10 ]; then
    REPORT+="\n_...and $((COMMIT_COUNT - 10)) more commits_\n"
  fi
  REPORT+="\n"
fi

# Footer
REPORT+="---\n\n"
REPORT+="_Generated by CI/CD Pipeline | ${TIMESTAMP}_\n"

REPORT=$(echo -e "$REPORT")

# Print report to console
echo ""
echo "=== Release Report ==="
echo -e "$REPORT"

#######################################
# SAVE JSON REPORT
#######################################
echo ""
echo "Saving JSON report..."

cat > release-report.json << EOF
{
  "version": "${VERSION}",
  "project": "${PROJECT_NAME}",
  "type": "fullstack",
  "branch": "${BITBUCKET_BRANCH}",
  "commit": "${BITBUCKET_COMMIT}",
  "timestamp": "$(get_iso_timestamp)",
  "overallStatus": "${OVERALL_STATUS}",
  "sonarqube": {
    "qualityGate": "${SONAR_QG_STATUS}",
    "bugs": "${SONAR_BUGS}",
    "vulnerabilities": "${SONAR_VULNS}",
    "codeSmells": "${SONAR_SMELLS}",
    "coverage": "${SONAR_COVERAGE}",
    "securityHotspots": "${SONAR_HOTSPOTS}"
  },
  "npmAudit": {
    "critical": ${NPM_CRITICAL},
    "high": ${NPM_HIGH},
    "moderate": ${NPM_MODERATE},
    "low": ${NPM_LOW},
    "total": ${NPM_TOTAL},
    "note": "Combined server + client"
  },
  "snyk": {
    "critical": ${SNYK_CRITICAL},
    "high": ${SNYK_HIGH},
    "medium": ${SNYK_MEDIUM},
    "low": ${SNYK_LOW},
    "note": "Combined server + client"
  },
  "commits": ${GIT_COMMITS_JSON}
}
EOF

echo "Saved release-report.json"

#######################################
# POST TO BITBUCKET PR
#######################################
if [ -n "$BITBUCKET_PR_ID" ]; then
  post_to_pr "$REPORT"
else
  echo ""
  echo "Not in PR context - report printed to console only"
fi

echo ""
echo "=== Release Report Complete ==="
