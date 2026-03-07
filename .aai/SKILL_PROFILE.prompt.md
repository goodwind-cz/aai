# Performance Profiling Skill

## Goal
Profile AAI workflow execution to identify bottlenecks and optimize resource usage. Track per-skill token usage, execution time, memory footprint, and cache efficiency.

## Scope
- Individual skill profiling
- Full workflow profiling (intake → TDD → validate → share)
- Historical performance analysis
- Comparative analysis (before/after optimizations)

## Metrics Tracked

### 1. Token Usage
- Input tokens per skill invocation
- Output tokens per skill invocation
- Token efficiency (output/input ratio)
- Cost per operation (based on model pricing)
- Cumulative token usage over time

### 2. Execution Time
- Wall clock time per skill
- Breakdown by operation phase:
  - File I/O time
  - Git operations time
  - External tool execution time (gh, npm, etc.)
  - LLM inference time
- Time spent waiting vs. active processing

### 3. Memory Usage
- Worktree disk usage
- Number of files created/modified
- Average file size
- Total project size growth
- Temporary file cleanup efficiency

### 4. Cache Performance
- File read cache hit rate
- Git operation cache usage
- Repeated pattern detection (similar operations)
- Prompt reuse opportunities

## Operations

### 1. Profile Single Skill (`/aai-profile <skill>`)

Profile a specific skill execution:

```bash
/aai-profile aai-intake

Profiling: aai-intake
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Execution Metrics:
  Duration:        3.2s
  Tokens In:       1,200
  Tokens Out:      450
  Cost:            $0.0024
  Status:          Success

Time Breakdown:
  File I/O:        0.4s (12.5%)
  Git Ops:         0.2s (6.3%)
  LLM Inference:   2.3s (71.9%)
  Other:           0.3s (9.4%)

Memory Impact:
  Files Created:   1
  Disk Usage:      +2.4 KB
  Temp Files:      0

Cache Performance:
  File Reads:      15 (12 cached, 80% hit rate)
  Git Ops:         3 (2 cached, 67% hit rate)

Bottleneck Analysis:
  ⚠️  71.9% of time spent in LLM inference
  ✓ Disk I/O is efficient
  ✓ Cache hit rate is good

Optimization Suggestions:
  1. Consider caching LLM responses for common intakes
  2. Current performance is within acceptable range
```

### 2. Profile Workflow (`/aai-profile --workflow`)

Profile a complete workflow from intake to share:

```bash
/aai-profile --workflow

Workflow Profiling: Full AAI Cycle
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Workflow Steps:
  1. aai-intake       →  3.2s,  1,650 tokens,  $0.0024
  2. aai-tdd (3x)     → 36.8s,  9,600 tokens,  $0.0192
  3. aai-validate     →  8.5s,  2,100 tokens,  $0.0042
  4. aai-share        →  4.1s,    800 tokens,  $0.0016

Total Metrics:
  Duration:        52.6s
  Total Tokens:    14,150
  Total Cost:      $0.0274
  Steps:           6
  Success Rate:    100%

Time Distribution:
  ████████████████████████████████░░░░░  69.9% - aai-tdd (3 cycles)
  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  16.2% - aai-validate
  ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   7.8% - aai-share
  ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   6.1% - aai-intake

Token Distribution:
  ████████████████████████████████░░░░░  67.8% - aai-tdd
  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  14.8% - aai-validate
  ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  11.7% - aai-intake
  ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5.7% - aai-share

Bottleneck Analysis:
  🔴 TDD cycles account for 69.9% of total time
  🟡 Three TDD cycles may be excessive for this change
  ✓ Validation and sharing are efficient

Optimization Suggestions:
  1. Reduce TDD cycles: Consider batching test cases
  2. TDD average cycle time: 12.3s (target: <10s)
  3. Consider parallel test execution
  4. Overall workflow time is acceptable (<60s)
```

### 3. Historical Analysis (`/aai-profile --history`)

Analyze performance trends over time:

```bash
/aai-profile --history --days 30

Performance Trends (Last 30 Days)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Operations:          156 total
Period:              Feb 5 - Mar 7, 2026

Average Metrics:
  Duration:          5.2s (±2.1s)
  Tokens:            1,574 (±890)
  Cost per op:       $0.0031 (±0.0018)

Performance Trends:
  ✓ Avg duration decreased 15% over last 30 days
  ✓ Token usage decreased 8% over last 30 days
  ⚠️  Cost per operation increased 3% (model pricing change)

Top 5 Slowest Operations:
  1. aai-validate (Feb 15) - 42.3s, 8,900 tokens
  2. aai-tdd (Feb 28)      - 38.7s, 7,200 tokens
  3. aai-validate (Mar 3)  - 35.1s, 6,800 tokens
  4. aai-tdd (Mar 5)       - 32.9s, 6,500 tokens
  5. aai-intake (Feb 20)   - 28.4s, 5,100 tokens

Top 5 Most Expensive Operations:
  1. aai-validate (Feb 15) - $0.0178
  2. aai-tdd (Feb 28)      - $0.0144
  3. aai-validate (Mar 3)  - $0.0136
  4. aai-tdd (Mar 5)       - $0.0130
  5. aai-intake (Feb 20)   - $0.0102

Skill Efficiency Rankings:
  1. aai-share          - 4.1s avg, 800 tokens avg, 100% success
  2. aai-intake         - 3.2s avg, 1,650 tokens avg, 97.8% success
  3. aai-worktree       - 1.8s avg, 600 tokens avg, 100% success
  4. aai-validate       - 8.5s avg, 2,100 tokens avg, 94.7% success
  5. aai-tdd            - 12.3s avg, 3,200 tokens avg, 93.8% success

Recommendations:
  1. ✓ Overall performance is improving
  2. ⚠️  Monitor validation times - trending upward
  3. ✓ Cache hit rates improved 12% over last 30 days
  4. Consider workflow optimization for TDD cycles
```

### 4. Compare Runs (`/aai-profile --compare <run1> <run2>`)

Compare two profiling runs:

```bash
/aai-profile --compare before-optimization after-optimization

Comparison: before-optimization vs after-optimization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Metric                    Before      After       Change
────────────────────────────────────────────────────────
Duration                  52.6s       38.4s       -27.0% ✓
Total Tokens              14,150      12,800      -9.5%  ✓
Total Cost                $0.0274     $0.0256     -6.6%  ✓
Cache Hit Rate            72%         89%         +17%   ✓
Temp Files Created        12          3           -75%   ✓

Per-Skill Changes:
────────────────────────────────────────────────────────
aai-intake
  Duration                3.2s        3.1s        -3.1%
  Tokens                  1,650       1,650       0%

aai-tdd (3 cycles)
  Duration                36.8s       24.2s       -34.2% ✓
  Tokens                  9,600       8,400       -12.5% ✓
  Avg cycle time          12.3s       8.1s        -34.1% ✓

aai-validate
  Duration                8.5s        7.4s        -12.9% ✓
  Tokens                  2,100       1,950       -7.1%  ✓

aai-share
  Duration                4.1s        3.7s        -9.8%  ✓
  Tokens                  800         800         0%

Impact Analysis:
  ✓ Optimization reduced workflow time by 14.2s (27%)
  ✓ TDD improvements had largest impact (34.2% faster)
  ✓ Token usage reduced across board
  ✓ Cache improvements contributed 15% of time savings

Verdict: OPTIMIZATION SUCCESSFUL
```

### 5. Live Profiling (`/aai-profile --live`)

Start live profiling for current session:

```bash
/aai-profile --live

Live Profiling Started
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Session ID: prof-20260307-123456
Output:     docs/ai/profiles/live-20260307-123456.jsonl

⚡ Profiling active. All AAI skills will be instrumented.
📊 Metrics will be recorded in real-time.
🛑 Stop profiling: /aai-profile --stop

[Skills will now log detailed metrics as they execute]
```

### 6. Generate Report (`/aai-profile --report`)

Generate comprehensive profiling report:

```bash
/aai-profile --report --output docs/ai/profiles/report-march.md

Generating Profiling Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Period:    Mar 1-7, 2026 (7 days)
Data:      89 operations analyzed

✓ Parsed profiling data
✓ Calculated statistics
✓ Generated charts
✓ Identified bottlenecks
✓ Created optimization roadmap

Report saved:
  Markdown:  docs/ai/profiles/report-march.md
  JSON:      docs/ai/profiles/report-march.json
  HTML:      docs/ai/profiles/report-march.html

Summary:
  Total Time:        7.8 hours
  Total Tokens:      140,066
  Total Cost:        $0.28
  Avg Operation:     5.2s, 1,574 tokens

Top Bottleneck:
  TDD cycles (3.2 hours, 41% of total time)

Optimization Potential:
  🎯 Target: 25% reduction in TDD time
  💰 Estimated savings: $0.07/week ($3.64/year)
  ⏱️  Time savings: 1.9 hours/week

Next steps:
  1. Review report: docs/ai/profiles/report-march.md
  2. Implement suggested optimizations
  3. Re-run profiling: /aai-profile --workflow
```

## Data Collection

### Profiling Data Format

Save to `docs/ai/profiles/<session-id>.jsonl`:

```json
{
  "timestamp": "2026-03-07T12:34:56Z",
  "session_id": "prof-20260307-123456",
  "skill": "aai-tdd",
  "operation": "red_phase",
  "metrics": {
    "duration_ms": 8234,
    "tokens": {
      "input": 2100,
      "output": 890,
      "cached": 450
    },
    "cost_usd": 0.0062,
    "memory": {
      "files_created": 2,
      "files_modified": 3,
      "files_deleted": 0,
      "disk_delta_kb": 4.2,
      "temp_files": 1
    },
    "cache": {
      "file_reads": 12,
      "file_reads_cached": 9,
      "git_ops": 3,
      "git_ops_cached": 2
    },
    "breakdown": {
      "file_io_ms": 320,
      "git_ops_ms": 180,
      "llm_inference_ms": 6800,
      "other_ms": 934
    }
  },
  "status": "success",
  "error": null
}
```

### Instrumentation

Add profiling hooks to AAI skills:

```javascript
// .aai/lib/profiler.mjs
export class Profiler {
  constructor(sessionId) {
    this.sessionId = sessionId;
    this.startTime = Date.now();
    this.metrics = {
      duration_ms: 0,
      tokens: { input: 0, output: 0, cached: 0 },
      cost_usd: 0,
      memory: {
        files_created: 0,
        files_modified: 0,
        files_deleted: 0,
        disk_delta_kb: 0,
        temp_files: 0
      },
      cache: {
        file_reads: 0,
        file_reads_cached: 0,
        git_ops: 0,
        git_ops_cached: 0
      },
      breakdown: {
        file_io_ms: 0,
        git_ops_ms: 0,
        llm_inference_ms: 0,
        other_ms: 0
      }
    };
  }

  recordFileIO(duration_ms, cached = false) {
    this.metrics.breakdown.file_io_ms += duration_ms;
    this.metrics.cache.file_reads++;
    if (cached) this.metrics.cache.file_reads_cached++;
  }

  recordGitOp(duration_ms, cached = false) {
    this.metrics.breakdown.git_ops_ms += duration_ms;
    this.metrics.cache.git_ops++;
    if (cached) this.metrics.cache.git_ops_cached++;
  }

  recordLLM(duration_ms, tokens_in, tokens_out, cached = 0, cost = 0) {
    this.metrics.breakdown.llm_inference_ms += duration_ms;
    this.metrics.tokens.input += tokens_in;
    this.metrics.tokens.output += tokens_out;
    this.metrics.tokens.cached += cached;
    this.metrics.cost_usd += cost;
  }

  recordMemory(files_created, files_modified, files_deleted, disk_delta_kb, temp_files) {
    this.metrics.memory.files_created += files_created;
    this.metrics.memory.files_modified += files_modified;
    this.metrics.memory.files_deleted += files_deleted;
    this.metrics.memory.disk_delta_kb += disk_delta_kb;
    this.metrics.memory.temp_files += temp_files;
  }

  finalize(skill, operation, status, error = null) {
    this.metrics.duration_ms = Date.now() - this.startTime;

    // Calculate "other" time
    const accounted =
      this.metrics.breakdown.file_io_ms +
      this.metrics.breakdown.git_ops_ms +
      this.metrics.breakdown.llm_inference_ms;
    this.metrics.breakdown.other_ms = this.metrics.duration_ms - accounted;

    const entry = {
      timestamp: new Date().toISOString(),
      session_id: this.sessionId,
      skill,
      operation,
      metrics: this.metrics,
      status,
      error
    };

    return entry;
  }
}
```

### Usage in Skills

```javascript
import { Profiler } from '.aai/lib/profiler.mjs';

async function runTDDCycle() {
  const prof = new Profiler('prof-20260307-123456');

  try {
    // File I/O
    const start = Date.now();
    const files = await readFiles();
    prof.recordFileIO(Date.now() - start);

    // Git operation
    const gitStart = Date.now();
    await gitCommit();
    prof.recordGitOp(Date.now() - gitStart);

    // LLM call
    const llmStart = Date.now();
    const response = await callLLM(prompt);
    prof.recordLLM(
      Date.now() - llmStart,
      response.usage.input_tokens,
      response.usage.output_tokens,
      response.usage.cached_tokens || 0,
      calculateCost(response.usage)
    );

    // Memory tracking
    prof.recordMemory(1, 2, 0, 4.2, 0);

    // Finalize
    const entry = prof.finalize('aai-tdd', 'red_phase', 'success');
    await saveProfileEntry(entry);

  } catch (error) {
    const entry = prof.finalize('aai-tdd', 'red_phase', 'error', error.message);
    await saveProfileEntry(entry);
  }
}
```

## Bottleneck Detection

### Automatic Detection

```javascript
function detectBottlenecks(profileData) {
  const bottlenecks = [];

  // Time bottlenecks
  const avgDuration = calculateAverage(profileData.map(p => p.metrics.duration_ms));
  profileData.forEach(p => {
    if (p.metrics.duration_ms > avgDuration * 2) {
      bottlenecks.push({
        type: 'time',
        severity: 'high',
        skill: p.skill,
        operation: p.operation,
        value: p.metrics.duration_ms,
        threshold: avgDuration * 2,
        message: `Operation took ${(p.metrics.duration_ms / 1000).toFixed(1)}s, 2x slower than average`
      });
    }
  });

  // Token bottlenecks
  const avgTokens = calculateAverage(profileData.map(p =>
    p.metrics.tokens.input + p.metrics.tokens.output
  ));
  profileData.forEach(p => {
    const totalTokens = p.metrics.tokens.input + p.metrics.tokens.output;
    if (totalTokens > avgTokens * 2) {
      bottlenecks.push({
        type: 'tokens',
        severity: 'medium',
        skill: p.skill,
        operation: p.operation,
        value: totalTokens,
        threshold: avgTokens * 2,
        message: `Operation used ${totalTokens} tokens, 2x more than average`
      });
    }
  });

  // Cache miss bottlenecks
  profileData.forEach(p => {
    const hitRate = p.metrics.cache.file_reads_cached / p.metrics.cache.file_reads;
    if (hitRate < 0.5 && p.metrics.cache.file_reads > 10) {
      bottlenecks.push({
        type: 'cache',
        severity: 'low',
        skill: p.skill,
        operation: p.operation,
        value: hitRate,
        threshold: 0.5,
        message: `Cache hit rate is ${(hitRate * 100).toFixed(1)}%, below 50% threshold`
      });
    }
  });

  // Memory bottlenecks
  profileData.forEach(p => {
    if (p.metrics.memory.temp_files > 5) {
      bottlenecks.push({
        type: 'memory',
        severity: 'low',
        skill: p.skill,
        operation: p.operation,
        value: p.metrics.memory.temp_files,
        threshold: 5,
        message: `Created ${p.metrics.memory.temp_files} temp files, cleanup may be needed`
      });
    }
  });

  return bottlenecks.sort((a, b) => {
    const severityOrder = { high: 0, medium: 1, low: 2 };
    return severityOrder[a.severity] - severityOrder[b.severity];
  });
}
```

## Optimization Suggestions

Based on profiling data, generate actionable recommendations:

```javascript
function generateOptimizations(profileData, bottlenecks) {
  const suggestions = [];

  // Time optimizations
  const slowSkills = bottlenecks.filter(b => b.type === 'time');
  if (slowSkills.length > 0) {
    slowSkills.forEach(b => {
      suggestions.push({
        priority: 'high',
        category: 'performance',
        title: `Optimize ${b.skill}/${b.operation}`,
        description: `Operation taking ${(b.value / 1000).toFixed(1)}s, investigate:`,
        actions: [
          'Profile LLM inference time - consider using faster model for simple operations',
          'Check for sequential operations that could be parallelized',
          'Review prompt size - reduce context if possible',
          'Consider caching results for similar inputs'
        ],
        potential_savings: {
          time_seconds: b.value - b.threshold,
          cost_usd: ((b.value - b.threshold) / 1000) * 0.0001
        }
      });
    });
  }

  // Token optimizations
  const tokenHeavy = bottlenecks.filter(b => b.type === 'tokens');
  if (tokenHeavy.length > 0) {
    suggestions.push({
      priority: 'medium',
      category: 'cost',
      title: 'Reduce token usage',
      description: `${tokenHeavy.length} operations using excessive tokens`,
      actions: [
        'Review prompts for unnecessary verbosity',
        'Use prompt caching for repeated context',
        'Consider smaller model for simple tasks',
        'Implement token budgets per operation'
      ],
      potential_savings: {
        tokens: tokenHeavy.reduce((sum, b) => sum + (b.value - b.threshold), 0),
        cost_usd: tokenHeavy.reduce((sum, b) =>
          sum + ((b.value - b.threshold) * 0.000002), 0
        )
      }
    });
  }

  // Cache optimizations
  const cacheMisses = bottlenecks.filter(b => b.type === 'cache');
  if (cacheMisses.length > 0) {
    suggestions.push({
      priority: 'low',
      category: 'efficiency',
      title: 'Improve cache hit rate',
      description: `${cacheMisses.length} operations with low cache utilization`,
      actions: [
        'Implement file content caching',
        'Cache git operation results',
        'Reuse read results within same operation',
        'Pre-warm cache for common files'
      ],
      potential_savings: {
        time_seconds: cacheMisses.length * 0.5,
        cost_usd: 0
      }
    });
  }

  return suggestions.sort((a, b) => {
    const priorityOrder = { high: 0, medium: 1, low: 2 };
    return priorityOrder[a.priority] - priorityOrder[b.priority];
  });
}
```

## Output Files

```
docs/ai/profiles/
├── live-<session-id>.jsonl       # Real-time profiling data
├── report-<date>.md              # Markdown report
├── report-<date>.json            # JSON data for analysis
├── report-<date>.html            # HTML dashboard (optional)
├── comparison-<id1>-<id2>.md     # Comparison reports
└── LATEST.md                     # Symlink to latest report
```

## Integration with METRICS.jsonl

Profiling data should feed into metrics:

```bash
# After profiling run
/aai-profile --export-metrics

✓ Exported profiling data to docs/ai/METRICS.jsonl
  Added 15 metric entries from profiling session
```

## Best Practices

1. **Profile regularly**: Run weekly or after code changes
2. **Baseline before optimizing**: Capture "before" profile
3. **Compare results**: Use --compare to validate improvements
4. **Focus on high-impact**: Prioritize bottlenecks with biggest impact
5. **Monitor trends**: Use --history to track long-term performance
6. **Automate**: Add profiling to CI/CD pipeline
7. **Share results**: Publish profiling reports to team

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Missing profiling data | Ensure skills are instrumented with Profiler |
| Inaccurate timings | Check system clock, avoid profiling under heavy load |
| High variance | Run multiple profiles and average results |
| Cache stats missing | Update instrumentation to track cache usage |
| Memory stats inaccurate | Ensure temp files are properly tracked |

## Output Format

```
AAI Performance Profile
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Session:     prof-20260307-123456
Skill:       aai-tdd (full workflow)
Duration:    36.8s
Tokens:      9,600 (7,200 input, 2,400 output)
Cost:        $0.0192

Time Breakdown:
  LLM Inference:     28.4s (77.2%) ████████████████████████████████
  File I/O:           4.2s (11.4%) █████
  Git Operations:     2.8s  (7.6%) ███
  Other:              1.4s  (3.8%) ██

Memory Impact:
  Files Created:      6
  Files Modified:     12
  Disk Usage:         +18.4 KB
  Temp Files:         2

Cache Performance:
  File Reads:         45 (36 cached, 80.0% hit rate)
  Git Operations:     9 (6 cached, 66.7% hit rate)

Bottlenecks Detected:
  🔴 HIGH: LLM inference time excessive (target: <20s)
  🟡 MEDIUM: 3 TDD cycles may be too many for simple change

Optimization Suggestions:
  1. [HIGH] Reduce prompt size for TDD cycles
     Impact: -30% time, -$0.006 cost

  2. [MEDIUM] Batch test cases to reduce cycles
     Impact: -25% time, -$0.004 cost

  3. [LOW] Improve cache hit rate for file reads
     Impact: -5% time, no cost change

Potential Savings:
  Time:       -18.4s (-50%)
  Cost:       -$0.010 (-52%)

Report saved:
  Profile:    docs/ai/profiles/prof-20260307-123456.jsonl
  Report:     docs/ai/profiles/report-20260307.md

Next steps:
  1. Review report: docs/ai/profiles/report-20260307.md
  2. Implement top 2 suggestions
  3. Re-profile: /aai-profile aai-tdd
  4. Compare: /aai-profile --compare before after
```

BEGIN NOW.
