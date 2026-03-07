# Metrics Dashboard Skill

## Goal
Parse `docs/ai/METRICS.jsonl` and generate an interactive HTML dashboard with visualizations of AAI workflow performance.

## Input
- `docs/ai/METRICS.jsonl` - JSONL file with metric entries

**Metric Entry Format:**
```json
{
  "timestamp": "2026-03-07T12:34:56Z",
  "skill": "aai-intake",
  "operation": "intake_prd",
  "tokens": {"input": 1200, "output": 450},
  "duration_ms": 3200,
  "status": "success",
  "metadata": {
    "ref_id": "PRD-001",
    "worktree": "feature-auth",
    "test_count": 12,
    "coverage": 87
  }
}
```

## Output
- `docs/ai/dashboard.html` - Interactive HTML dashboard
- `docs/ai/dashboard-data.json` - Processed metrics in JSON format

## Dashboard Sections

### 1. Overview Summary

Top-level KPIs:
```
┌─────────────────────────────────────────────────────────────┐
│ AAI Workflow Metrics                                        │
│ Period: <start-date> to <end-date>                          │
├─────────────────────────────────────────────────────────────┤
│ Total Operations:      <count>                              │
│ Total Tokens:          <input + output>                     │
│ Average Duration:      <ms>                                 │
│ Success Rate:          <percentage>%                        │
│ Active Worktrees:      <count>                              │
│ Published Reports:     <count>                              │
└─────────────────────────────────────────────────────────────┘
```

### 2. Token Usage Over Time

**Line chart:**
- X-axis: Date/time
- Y-axis: Token count
- Two lines: Input tokens (blue), Output tokens (green)
- Shows trends and spikes

**Chart data processing:**
```javascript
// Group by hour/day/week based on time range
const tokensByPeriod = metrics.reduce((acc, m) => {
  const period = formatPeriod(m.timestamp);
  if (!acc[period]) acc[period] = {input: 0, output: 0};
  acc[period].input += m.tokens.input;
  acc[period].output += m.tokens.output;
  return acc;
}, {});
```

### 3. TDD Cycle Analytics

**Metrics:**
- Average cycle time (red → green → refactor)
- Test pass/fail ratio
- Coverage improvements per cycle
- Most common failure patterns

**Bar chart:**
- X-axis: TDD cycle stages (red, green, refactor)
- Y-axis: Average duration (seconds)

**Table:**
```
┌────────┬───────────┬────────────┬──────────┬──────────┐
│ Cycle  │ Duration  │ Tests      │ Coverage │ Status   │
├────────┼───────────┼────────────┼──────────┼──────────┤
│ TDD-01 │   45s     │ 3 → 3 pass │   72%    │ Complete │
│ TDD-02 │   67s     │ 5 → 4 pass │   81%    │ Complete │
│ TDD-03 │   52s     │ 4 → 4 pass │   87%    │ Complete │
└────────┴───────────┴────────────┴──────────┴──────────┘
```

### 4. Worktree Efficiency

**Metrics:**
- Average lifespan per worktree
- Operations per worktree
- Most active worktrees
- Stale worktree detection (>7 days inactive)

**Pie chart:**
- Worktree distribution by operation count

**Table:**
```
┌────────────────┬────────────┬────────────┬──────────────┐
│ Worktree       │ Operations │ Lifespan   │ Status       │
├────────────────┼────────────┼────────────┼──────────────┤
│ feature-auth   │     23     │   3 days   │ Active       │
│ bugfix-login   │     12     │   1 day    │ Active       │
│ refactor-db    │      8     │   9 days   │ Stale        │
└────────────────┴────────────┴────────────┴──────────────┘
```

### 5. Publishing Statistics

**Metrics:**
- Documents published per day/week
- Average publish time
- Most published document types
- Published URL history

**Line chart:**
- X-axis: Date
- Y-axis: Number of publishes

**Table:**
```
┌────────────────────────┬─────────────┬──────────┬─────────────────┐
│ Document               │ Timestamp   │ Duration │ URL             │
├────────────────────────┼─────────────┼──────────┼─────────────────┤
│ validation-report.md   │ Mar 7 12:30 │   4.2s   │ example.com/... │
│ dashboard.html         │ Mar 7 11:15 │   3.8s   │ example.com/... │
└────────────────────────┴─────────────┴──────────┴─────────────────┘
```

### 6. Skill Usage Frequency

**Bar chart:**
- X-axis: Skill name
- Y-axis: Number of invocations

**Table with details:**
```
┌────────────────────┬───────────┬─────────────┬──────────────┬────────────┐
│ Skill              │ Uses      │ Avg Tokens  │ Avg Duration │ Success %  │
├────────────────────┼───────────┼─────────────┼──────────────┼────────────┤
│ aai-intake         │    45     │    1,650    │    3.2s      │   97.8%    │
│ aai-validate       │    38     │    2,100    │    8.5s      │   94.7%    │
│ aai-tdd            │    32     │    3,200    │   12.3s      │   93.8%    │
│ aai-share          │    18     │      800    │    4.1s      │  100.0%    │
│ aai-worktree       │    15     │      600    │    1.8s      │  100.0%    │
└────────────────────┴───────────┴─────────────┴──────────────┴────────────┘
```

## Implementation

### Parse METRICS.jsonl

```javascript
const fs = require('fs');
const path = require('path');

function parseMetrics(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').split('\n').filter(l => l.trim());
  return lines.map(line => JSON.parse(line));
}

const metrics = parseMetrics('docs/ai/METRICS.jsonl');
```

### Calculate Summary Stats

```javascript
function calculateSummary(metrics) {
  const total = metrics.length;
  const totalTokens = metrics.reduce((sum, m) =>
    sum + (m.tokens?.input || 0) + (m.tokens?.output || 0), 0
  );
  const avgDuration = metrics.reduce((sum, m) =>
    sum + (m.duration_ms || 0), 0
  ) / total;
  const successRate = metrics.filter(m =>
    m.status === 'success'
  ).length / total * 100;

  const worktrees = new Set(metrics
    .filter(m => m.metadata?.worktree)
    .map(m => m.metadata.worktree)
  );

  const publishes = metrics.filter(m =>
    m.skill === 'aai-share' && m.status === 'success'
  ).length;

  return {
    total,
    totalTokens,
    avgDuration: Math.round(avgDuration),
    successRate: successRate.toFixed(1),
    activeWorktrees: worktrees.size,
    publishes
  };
}
```

### Generate Charts (Chart.js)

```html
<!DOCTYPE html>
<html>
<head>
  <title>AAI Metrics Dashboard</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      margin: 0;
      padding: 20px;
      background: #f5f5f5;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
      background: white;
      padding: 30px;
      border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    h1 {
      color: #333;
      border-bottom: 2px solid #4CAF50;
      padding-bottom: 10px;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin: 30px 0;
    }
    .summary-card {
      background: #f9f9f9;
      padding: 20px;
      border-radius: 6px;
      border-left: 4px solid #4CAF50;
    }
    .summary-card h3 {
      margin: 0 0 10px 0;
      color: #666;
      font-size: 14px;
      font-weight: normal;
    }
    .summary-card .value {
      font-size: 28px;
      font-weight: bold;
      color: #333;
    }
    .chart-section {
      margin: 40px 0;
    }
    .chart-section h2 {
      color: #333;
      margin-bottom: 20px;
    }
    .chart-container {
      position: relative;
      height: 300px;
      margin-bottom: 40px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 20px 0;
    }
    th, td {
      padding: 12px;
      text-align: left;
      border-bottom: 1px solid #ddd;
    }
    th {
      background: #f9f9f9;
      font-weight: 600;
      color: #666;
    }
    .status-success { color: #4CAF50; }
    .status-error { color: #f44336; }
    .footer {
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #ddd;
      color: #999;
      font-size: 14px;
      text-align: center;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>AAI Workflow Metrics Dashboard</h1>
    <p>Period: <span id="period"></span></p>

    <div class="summary">
      <div class="summary-card">
        <h3>Total Operations</h3>
        <div class="value" id="total-ops"></div>
      </div>
      <div class="summary-card">
        <h3>Total Tokens</h3>
        <div class="value" id="total-tokens"></div>
      </div>
      <div class="summary-card">
        <h3>Avg Duration</h3>
        <div class="value" id="avg-duration"></div>
      </div>
      <div class="summary-card">
        <h3>Success Rate</h3>
        <div class="value" id="success-rate"></div>
      </div>
      <div class="summary-card">
        <h3>Active Worktrees</h3>
        <div class="value" id="worktrees"></div>
      </div>
      <div class="summary-card">
        <h3>Published Reports</h3>
        <div class="value" id="publishes"></div>
      </div>
    </div>

    <div class="chart-section">
      <h2>Token Usage Over Time</h2>
      <div class="chart-container">
        <canvas id="tokenChart"></canvas>
      </div>
    </div>

    <div class="chart-section">
      <h2>TDD Cycle Duration</h2>
      <div class="chart-container">
        <canvas id="tddChart"></canvas>
      </div>
    </div>

    <div class="chart-section">
      <h2>Skill Usage Frequency</h2>
      <div class="chart-container">
        <canvas id="skillChart"></canvas>
      </div>
      <table id="skillTable"></table>
    </div>

    <div class="chart-section">
      <h2>Worktree Activity</h2>
      <table id="worktreeTable"></table>
    </div>

    <div class="footer">
      Generated by AAI Dashboard Skill | <span id="generated-at"></span>
    </div>
  </div>

  <script>
    // Data will be injected here
    const metricsData = {{METRICS_DATA}};

    // Render dashboard
    renderDashboard(metricsData);
  </script>
</body>
</html>
```

### Dashboard Generation Script

Create `.aai/scripts/generate-dashboard.mjs`:

```javascript
#!/usr/bin/env node
import fs from 'fs';
import path from 'path';

function parseMetrics(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n').filter(l => l.trim());
  return lines.map(line => JSON.parse(line));
}

function calculateStats(metrics) {
  // Calculate summary stats
  const summary = {
    total: metrics.length,
    totalTokens: 0,
    avgDuration: 0,
    successRate: 0,
    worktrees: new Set(),
    publishes: 0
  };

  metrics.forEach(m => {
    summary.totalTokens += (m.tokens?.input || 0) + (m.tokens?.output || 0);
    summary.avgDuration += m.duration_ms || 0;
    if (m.status === 'success') summary.successRate++;
    if (m.metadata?.worktree) summary.worktrees.add(m.metadata.worktree);
    if (m.skill === 'aai-share' && m.status === 'success') summary.publishes++;
  });

  summary.avgDuration = Math.round(summary.avgDuration / summary.total);
  summary.successRate = ((summary.successRate / summary.total) * 100).toFixed(1);
  summary.worktrees = summary.worktrees.size;

  return summary;
}

function groupTokensByTime(metrics) {
  const grouped = {};
  metrics.forEach(m => {
    const date = new Date(m.timestamp).toISOString().split('T')[0];
    if (!grouped[date]) grouped[date] = { input: 0, output: 0 };
    grouped[date].input += m.tokens?.input || 0;
    grouped[date].output += m.tokens?.output || 0;
  });
  return grouped;
}

function calculateSkillStats(metrics) {
  const skills = {};
  metrics.forEach(m => {
    if (!skills[m.skill]) {
      skills[m.skill] = {
        count: 0,
        totalTokens: 0,
        totalDuration: 0,
        successes: 0
      };
    }
    skills[m.skill].count++;
    skills[m.skill].totalTokens += (m.tokens?.input || 0) + (m.tokens?.output || 0);
    skills[m.skill].totalDuration += m.duration_ms || 0;
    if (m.status === 'success') skills[m.skill].successes++;
  });

  return Object.entries(skills).map(([name, stats]) => ({
    name,
    count: stats.count,
    avgTokens: Math.round(stats.totalTokens / stats.count),
    avgDuration: (stats.totalDuration / stats.count / 1000).toFixed(1),
    successRate: ((stats.successes / stats.count) * 100).toFixed(1)
  })).sort((a, b) => b.count - a.count);
}

function generateDashboard(metricsPath, outputPath) {
  const metrics = parseMetrics(metricsPath);
  const summary = calculateStats(metrics);
  const tokensByTime = groupTokensByTime(metrics);
  const skillStats = calculateSkillStats(metrics);

  const data = {
    summary,
    tokensByTime,
    skillStats,
    generatedAt: new Date().toISOString()
  };

  // Save processed data
  fs.writeFileSync(
    path.join(path.dirname(outputPath), 'dashboard-data.json'),
    JSON.stringify(data, null, 2)
  );

  // Generate HTML (template would be here)
  const html = generateHTML(data);
  fs.writeFileSync(outputPath, html);

  return data;
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const metricsPath = process.argv[2] || 'docs/ai/METRICS.jsonl';
  const outputPath = process.argv[3] || 'docs/ai/dashboard.html';

  const data = generateDashboard(metricsPath, outputPath);
  console.log(`Dashboard generated: ${outputPath}`);
  console.log(`Summary: ${data.summary.total} operations, ${data.summary.totalTokens} tokens`);
}

export { generateDashboard };
```

## Usage

### Generate Dashboard

```bash
/aai-dashboard

Generating metrics dashboard...

✓ Parsed 156 metric entries from docs/ai/METRICS.jsonl
✓ Calculated summary statistics
✓ Generated charts and tables
✓ Dashboard saved to docs/ai/dashboard.html
✓ Data saved to docs/ai/dashboard-data.json

Summary:
  Total Operations:      156
  Total Tokens:          245,800
  Average Duration:      5.2s
  Success Rate:          96.2%
  Active Worktrees:      5
  Published Reports:     12

Open dashboard: file://docs/ai/dashboard.html
```

### Publish Dashboard

```bash
/aai-dashboard --publish

✓ Dashboard generated
✓ Publishing to Cloudflare Pages...
✓ Published: https://your-project.aai-reports.pages.dev/dashboard

Share link: https://your-project.aai-reports.pages.dev/dashboard
```

### Filter by Date Range

```bash
/aai-dashboard --from 2026-03-01 --to 2026-03-07

Generating dashboard for period: Mar 1 - Mar 7, 2026
✓ Filtered 89 entries (out of 156 total)
✓ Dashboard saved to docs/ai/dashboard.html
```

### Filter by Skill

```bash
/aai-dashboard --skill aai-tdd

Generating TDD-specific dashboard...
✓ Filtered 32 TDD entries
✓ Dashboard saved to docs/ai/dashboard-tdd.html
```

## Operations

### 1. Generate Basic Dashboard

```
/aai-dashboard

[Parses METRICS.jsonl, generates HTML with all sections]
```

### 2. Generate and Publish

```
/aai-dashboard --publish

[Generates dashboard, then calls /aai-share docs/ai/dashboard.html]
```

### 3. Time Range Filter

```
/aai-dashboard --from 2026-03-01 --to 2026-03-07

[Only include metrics within date range]
```

### 4. Skill-Specific Dashboard

```
/aai-dashboard --skill aai-tdd

[Generate dashboard focusing on single skill]
```

### 5. Export Data Only

```
/aai-dashboard --data-only

[Generate dashboard-data.json without HTML]
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `METRICS.jsonl not found` | Ensure metrics are being recorded by AAI skills |
| Charts not rendering | Check browser console, verify Chart.js CDN |
| Empty dashboard | No metrics recorded yet, run some AAI workflows |
| Parsing errors | Check METRICS.jsonl for malformed JSON lines |
| Missing data fields | Older metrics may not have all fields, filter by date |

## Integration with /aai-share

Dashboard is designed to be shareable:

```bash
# Generate dashboard
/aai-dashboard

# Publish to Cloudflare Pages
/aai-share docs/ai/dashboard.html
```

## Best Practices

1. **Generate regularly**: Run weekly or after major milestones
2. **Publish for team review**: Share dashboards with stakeholders
3. **Monitor trends**: Look for token usage spikes or duration increases
4. **Clean old metrics**: Archive metrics older than 90 days
5. **Compare periods**: Generate multiple dashboards for different date ranges

## Output Format

```
AAI Metrics Dashboard
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Generated: 2026-03-07 12:34:56 UTC
Period:    2026-02-15 to 2026-03-07 (21 days)

Summary:
  Total Operations:      156
  Total Tokens:          245,800
  Average Duration:      5.2s
  Success Rate:          96.2%
  Active Worktrees:      5
  Published Reports:     12

Dashboard saved:
  HTML:  docs/ai/dashboard.html
  Data:  docs/ai/dashboard-data.json
  Size:  127 KB

Top Skills:
  1. aai-intake          45 uses, 1,650 avg tokens
  2. aai-validate        38 uses, 2,100 avg tokens
  3. aai-tdd             32 uses, 3,200 avg tokens

Next steps:
  - Open: file://docs/ai/dashboard.html
  - Publish: /aai-share docs/ai/dashboard.html
  - Filter: /aai-dashboard --skill aai-tdd
```

BEGIN NOW.
