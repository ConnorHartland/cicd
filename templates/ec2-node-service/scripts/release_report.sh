#!/bin/bash
# release_report.sh
# Generates a consolidated security/quality report for releases
# Posts markdown summary to PR + generates full HTML report artifact

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/report_utils.sh"

echo "=== Generating Release Security Report ==="

# Extract version from branch name (release/X.X.X)
VERSION=${BITBUCKET_BRANCH#release/}
echo "Release Version: ${VERSION}"

# Get project info
PROJECT_KEY=$(get_project_key)
PROJECT_NAME=$(node -p "require('./package.json').name" 2>/dev/null || echo "Unknown Project")

#######################################
# RUN SCANS
#######################################
run_npm_audit
extract_npm_details
echo "npm audit - Critical: ${NPM_CRITICAL}, High: ${NPM_HIGH}, Moderate: ${NPM_MODERATE}, Low: ${NPM_LOW}"

run_snyk_scan
extract_snyk_details
if [ -n "$SNYK_TOKEN" ]; then
  echo "Snyk - Critical: ${SNYK_CRITICAL}, High: ${SNYK_HIGH}, Medium: ${SNYK_MEDIUM}, Low: ${SNYK_LOW}"
else
  echo "SNYK_TOKEN not set - skipping Snyk scan"
fi

fetch_sonarqube "$PROJECT_KEY"
fetch_sonar_issues "$PROJECT_KEY"
echo "SonarQube - QG: ${SONAR_QG_STATUS}, Bugs: ${SONAR_BUGS}, Vulns: ${SONAR_VULNS}"

#######################################
# DETERMINE OVERALL STATUS
#######################################
OVERALL_STATUS="PASSED"
OVERALL_ICON=":white_check_mark:"
OVERALL_CLASS="status-pass"

if [ "$SONAR_QG_STATUS" = "ERROR" ] || [ "$NPM_CRITICAL" -gt 0 ] || [ "$SNYK_CRITICAL" -gt 0 ]; then
  OVERALL_STATUS="FAILED"
  OVERALL_ICON=":x:"
  OVERALL_CLASS="status-fail"
elif [ "$NPM_HIGH" -gt 0 ] || [ "$SNYK_HIGH" -gt 0 ]; then
  OVERALL_STATUS="WARNINGS"
  OVERALL_ICON=":warning:"
  OVERALL_CLASS="status-warn"
fi

TIMESTAMP=$(get_timestamp)
ARTIFACTS_URL=$(get_artifacts_url)

#######################################
# BUILD MARKDOWN REPORT (PR Comment)
#######################################
echo ""
echo "Building markdown report..."

REPORT="## :package: Release Report - v${VERSION}\n\n"
REPORT+="**Project:** ${PROJECT_NAME}\n"
REPORT+="**Branch:** ${BITBUCKET_BRANCH}\n"
REPORT+="**Commit:** ${BITBUCKET_COMMIT:0:7}\n"
REPORT+="**Overall Status:** ${OVERALL_ICON} ${OVERALL_STATUS}\n\n"
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
    REPORT+="\n_...and $((SONAR_ISSUE_COUNT - 5)) more (see HTML report)_\n"
  fi
  REPORT+="\n"
fi

if [ -n "$SONAR_HOST_URL" ]; then
  REPORT+="[View Full SonarQube Report](${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY})\n\n"
fi

# npm audit Section
REPORT+="---\n\n"
REPORT+="### :package: Dependency Audit (npm)\n\n"

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
    NPM_TOP5=$(echo "$NPM_DETAILS" | head -5 | while IFS='|' read -r severity pkg desc; do
      echo "| ${severity} | ${pkg} | ${desc} |"
    done)
    REPORT+="\n**Critical/High Vulnerabilities:**\n\n"
    REPORT+="| Severity | Package | Description |\n"
    REPORT+="|----------|---------|-------------|\n"
    REPORT+="${NPM_TOP5}\n"
    if [ "$NPM_DETAIL_COUNT" -gt 5 ]; then
      REPORT+="\n_...and $((NPM_DETAIL_COUNT - 5)) more (see HTML report)_\n"
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
  REPORT+="| Severity | Count |\n"
  REPORT+="|----------|-------|\n"
  REPORT+="| :octagonal_sign: Critical | ${SNYK_CRITICAL} |\n"
  REPORT+="| :bangbang: High | ${SNYK_HIGH} |\n"
  REPORT+="| :warning: Medium | ${SNYK_MEDIUM} |\n"
  REPORT+="| :information_source: Low | ${SNYK_LOW} |\n\n"

  if [ -n "$SNYK_DETAILS" ]; then
    SNYK_DETAIL_COUNT=$((SNYK_CRITICAL + SNYK_HIGH))
    SNYK_TOP5=$(echo "$SNYK_DETAILS" | head -5 | while IFS='|' read -r severity pkg desc; do
      echo "| ${severity} | ${pkg} | ${desc} |"
    done)
    REPORT+="\n**Critical/High Vulnerabilities:**\n\n"
    REPORT+="| Severity | Package | Description |\n"
    REPORT+="|----------|---------|-------------|\n"
    REPORT+="${SNYK_TOP5}\n"
    if [ "$SNYK_DETAIL_COUNT" -gt 5 ]; then
      REPORT+="\n_...and $((SNYK_DETAIL_COUNT - 5)) more (see HTML report)_\n"
    fi
    REPORT+="\n"
  fi
fi

# Footer with artifact link
REPORT+="---\n\n"
REPORT+=":page_facing_up: **[View Full HTML Report](${ARTIFACTS_URL})**\n\n"
REPORT+="_Generated by CI/CD Pipeline | ${TIMESTAMP}_\n"

REPORT=$(echo -e "$REPORT")

# Print report to console
echo ""
echo "=== Release Report (Markdown) ==="
echo -e "$REPORT"

#######################################
# BUILD HTML REPORT
#######################################
echo ""
echo "Building HTML report..."

# Helper to generate severity badge
badge() {
  local severity=$1
  local count=$2
  case $severity in
    critical|CRITICAL) echo "<span class=\"badge badge-critical\">${count} Critical</span>" ;;
    high|HIGH) echo "<span class=\"badge badge-high\">${count} High</span>" ;;
    medium|MEDIUM|moderate|MODERATE) echo "<span class=\"badge badge-medium\">${count} Medium</span>" ;;
    low|LOW) echo "<span class=\"badge badge-low\">${count} Low</span>" ;;
    *) echo "<span class=\"badge\">${count}</span>" ;;
  esac
}

cat > release-report.html << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Release Report - v${VERSION}</title>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      margin: 0;
      padding: 40px;
      background: #f4f5f7;
      color: #172b4d;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    .card {
      background: white;
      border-radius: 8px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.12);
      margin-bottom: 24px;
      overflow: hidden;
    }
    .card-header {
      padding: 16px 24px;
      border-bottom: 1px solid #dfe1e6;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .card-header h2 { margin: 0; font-size: 18px; }
    .card-body { padding: 24px; }
    .header {
      background: linear-gradient(135deg, #0052cc 0%, #0747a6 100%);
      color: white;
      padding: 32px;
      border-radius: 8px;
      margin-bottom: 24px;
    }
    .header h1 { margin: 0 0 16px 0; font-size: 28px; }
    .header-meta { display: flex; gap: 24px; flex-wrap: wrap; opacity: 0.9; }
    .header-meta span { display: flex; align-items: center; gap: 6px; }
    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 16px;
      border-radius: 20px;
      font-weight: 600;
      font-size: 14px;
    }
    .status-pass { background: #e3fcef; color: #006644; }
    .status-fail { background: #ffebe6; color: #bf2600; }
    .status-warn { background: #fffae6; color: #ff8b00; }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 600;
    }
    .badge-critical { background: #de350b; color: white; }
    .badge-high { background: #ff5630; color: white; }
    .badge-medium { background: #ff991f; color: #172b4d; }
    .badge-low { background: #6b778c; color: white; }
    .badge-ok { background: #00875a; color: white; }
    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 16px;
    }
    .metric {
      text-align: center;
      padding: 16px;
      background: #f4f5f7;
      border-radius: 8px;
    }
    .metric-value { font-size: 32px; font-weight: 700; color: #0052cc; }
    .metric-label { font-size: 12px; color: #6b778c; text-transform: uppercase; margin-top: 4px; }
    .severity-summary {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      margin-bottom: 16px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    th, td {
      padding: 12px;
      text-align: left;
      border-bottom: 1px solid #dfe1e6;
    }
    th { background: #f4f5f7; font-weight: 600; }
    tr:hover { background: #fafbfc; }
    details { margin-top: 16px; }
    summary {
      cursor: pointer;
      padding: 12px 16px;
      background: #f4f5f7;
      border-radius: 4px;
      font-weight: 600;
      user-select: none;
    }
    summary:hover { background: #ebecf0; }
    details[open] summary { border-radius: 4px 4px 0 0; }
    .details-content {
      border: 1px solid #dfe1e6;
      border-top: none;
      border-radius: 0 0 4px 4px;
      max-height: 400px;
      overflow-y: auto;
    }
    .empty-state {
      text-align: center;
      padding: 32px;
      color: #6b778c;
    }
    .empty-state svg { width: 48px; height: 48px; margin-bottom: 12px; }
    .footer {
      text-align: center;
      padding: 24px;
      color: #6b778c;
      font-size: 12px;
    }
    .icon { width: 20px; height: 20px; }
    a { color: #0052cc; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <!-- Header -->
    <div class="header">
      <h1>📦 Release Report - v${VERSION}</h1>
      <div class="header-meta">
        <span>📁 ${PROJECT_NAME}</span>
        <span>🌿 ${BITBUCKET_BRANCH}</span>
        <span>🔗 ${BITBUCKET_COMMIT:0:7}</span>
      </div>
      <div style="margin-top: 16px;">
        <span class="status-badge ${OVERALL_CLASS}">
          $([ "$OVERALL_STATUS" = "PASSED" ] && echo "✓" || ([ "$OVERALL_STATUS" = "FAILED" ] && echo "✗" || echo "⚠"))
          ${OVERALL_STATUS}
        </span>
      </div>
    </div>

    <!-- SonarQube Card -->
    <div class="card">
      <div class="card-header">
        <span style="font-size: 24px;">🔍</span>
        <h2>Code Quality (SonarQube)</h2>
        $(if [ "$SONAR_QG_STATUS" = "OK" ]; then
          echo '<span class="badge badge-ok">Quality Gate Passed</span>'
        elif [ "$SONAR_QG_STATUS" = "ERROR" ]; then
          echo '<span class="badge badge-critical">Quality Gate Failed</span>'
        else
          echo "<span class=\"badge\">${SONAR_QG_STATUS}</span>"
        fi)
      </div>
      <div class="card-body">
        <div class="metrics-grid">
          <div class="metric">
            <div class="metric-value">${SONAR_BUGS:-0}</div>
            <div class="metric-label">🐛 Bugs</div>
          </div>
          <div class="metric">
            <div class="metric-value">${SONAR_VULNS:-0}</div>
            <div class="metric-label">🔒 Vulnerabilities</div>
          </div>
          <div class="metric">
            <div class="metric-value">${SONAR_SMELLS:-0}</div>
            <div class="metric-label">💩 Code Smells</div>
          </div>
          <div class="metric">
            <div class="metric-value">${SONAR_HOTSPOTS:-0}</div>
            <div class="metric-label">🔥 Hotspots</div>
          </div>
          <div class="metric">
            <div class="metric-value">${SONAR_COVERAGE:-0}%</div>
            <div class="metric-label">📊 Coverage</div>
          </div>
        </div>
HTMLEOF

# Add SonarQube issues if present
if [ -n "$SONAR_DETAILS" ]; then
  cat >> release-report.html << 'HTMLEOF'
        <details>
          <summary>View Blocker/Critical Issues</summary>
          <div class="details-content">
            <table>
              <thead>
                <tr><th>Severity</th><th>Message</th><th>File</th></tr>
              </thead>
              <tbody>
HTMLEOF
  echo "$SONAR_DETAILS" | while IFS='|' read -r severity msg file; do
    echo "                <tr><td><span class=\"badge badge-critical\">${severity}</span></td><td>${msg}</td><td>${file}</td></tr>" >> release-report.html
  done
  cat >> release-report.html << 'HTMLEOF'
              </tbody>
            </table>
          </div>
        </details>
HTMLEOF
fi

# Add SonarQube link
if [ -n "$SONAR_HOST_URL" ]; then
  echo "        <p style=\"margin-top: 16px;\"><a href=\"${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY}\" target=\"_blank\">View Full SonarQube Dashboard →</a></p>" >> release-report.html
fi

cat >> release-report.html << 'HTMLEOF'
      </div>
    </div>

    <!-- npm audit Card -->
    <div class="card">
      <div class="card-header">
        <span style="font-size: 24px;">📦</span>
        <h2>Dependency Audit (npm)</h2>
      </div>
      <div class="card-body">
HTMLEOF

if [ "$NPM_TOTAL" -eq 0 ]; then
  cat >> release-report.html << 'HTMLEOF'
        <div class="empty-state">
          <div style="font-size: 48px;">✅</div>
          <p>No vulnerabilities found</p>
        </div>
HTMLEOF
else
  cat >> release-report.html << HTMLEOF
        <div class="severity-summary">
          $(badge critical "$NPM_CRITICAL")
          $(badge high "$NPM_HIGH")
          $(badge medium "$NPM_MODERATE")
          $(badge low "$NPM_LOW")
        </div>
        <p><strong>Total: ${NPM_TOTAL} vulnerabilities</strong></p>
HTMLEOF

  if [ -n "$NPM_DETAILS" ]; then
    cat >> release-report.html << 'HTMLEOF'
        <details open>
          <summary>View Critical/High Vulnerabilities</summary>
          <div class="details-content">
            <table>
              <thead>
                <tr><th>Severity</th><th>Package</th><th>Description</th></tr>
              </thead>
              <tbody>
HTMLEOF
    echo "$NPM_DETAILS" | while IFS='|' read -r severity pkg desc; do
      local badge_class="badge-high"
      [ "$severity" = "CRITICAL" ] && badge_class="badge-critical"
      echo "                <tr><td><span class=\"badge ${badge_class}\">${severity}</span></td><td>${pkg}</td><td>${desc}</td></tr>" >> release-report.html
    done
    cat >> release-report.html << 'HTMLEOF'
              </tbody>
            </table>
          </div>
        </details>
HTMLEOF
  fi
fi

cat >> release-report.html << 'HTMLEOF'
      </div>
    </div>

    <!-- Snyk Card -->
    <div class="card">
      <div class="card-header">
        <span style="font-size: 24px;">🛡️</span>
        <h2>Security Scan (Snyk)</h2>
      </div>
      <div class="card-body">
HTMLEOF

if [ -z "$SNYK_TOKEN" ]; then
  cat >> release-report.html << 'HTMLEOF'
        <div class="empty-state">
          <div style="font-size: 48px;">⏭️</div>
          <p>Snyk scan skipped (SNYK_TOKEN not configured)</p>
        </div>
HTMLEOF
elif [ "$SNYK_CRITICAL" -eq 0 ] && [ "$SNYK_HIGH" -eq 0 ] && [ "$SNYK_MEDIUM" -eq 0 ] && [ "$SNYK_LOW" -eq 0 ]; then
  cat >> release-report.html << 'HTMLEOF'
        <div class="empty-state">
          <div style="font-size: 48px;">✅</div>
          <p>No vulnerabilities found</p>
        </div>
HTMLEOF
else
  SNYK_TOTAL=$((SNYK_CRITICAL + SNYK_HIGH + SNYK_MEDIUM + SNYK_LOW))
  cat >> release-report.html << HTMLEOF
        <div class="severity-summary">
          $(badge critical "$SNYK_CRITICAL")
          $(badge high "$SNYK_HIGH")
          $(badge medium "$SNYK_MEDIUM")
          $(badge low "$SNYK_LOW")
        </div>
        <p><strong>Total: ${SNYK_TOTAL} vulnerabilities</strong></p>
HTMLEOF

  if [ -n "$SNYK_DETAILS" ]; then
    cat >> release-report.html << 'HTMLEOF'
        <details open>
          <summary>View Critical/High Vulnerabilities</summary>
          <div class="details-content">
            <table>
              <thead>
                <tr><th>Severity</th><th>Package</th><th>Description</th></tr>
              </thead>
              <tbody>
HTMLEOF
    echo "$SNYK_DETAILS" | while IFS='|' read -r severity pkg desc; do
      local badge_class="badge-high"
      [ "$severity" = "CRITICAL" ] && badge_class="badge-critical"
      echo "                <tr><td><span class=\"badge ${badge_class}\">${severity}</span></td><td>${pkg}</td><td>${desc}</td></tr>" >> release-report.html
    done
    cat >> release-report.html << 'HTMLEOF'
              </tbody>
            </table>
          </div>
        </details>
HTMLEOF
  fi
fi

cat >> release-report.html << HTMLEOF
      </div>
    </div>

    <!-- Footer -->
    <div class="footer">
      Generated by CI/CD Pipeline | ${TIMESTAMP}
    </div>
  </div>
</body>
</html>
HTMLEOF

echo "Saved release-report.html"

#######################################
# SAVE JSON REPORT
#######################################
echo ""
echo "Saving JSON report..."

cat > release-report.json << EOF
{
  "version": "${VERSION}",
  "project": "${PROJECT_NAME}",
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
    "total": ${NPM_TOTAL}
  },
  "snyk": {
    "critical": ${SNYK_CRITICAL},
    "high": ${SNYK_HIGH},
    "medium": ${SNYK_MEDIUM},
    "low": ${SNYK_LOW}
  }
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
