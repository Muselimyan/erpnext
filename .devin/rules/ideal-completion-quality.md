---
trigger: always_on
description: Quality bar for finished work and regression tests
---

# Ideal Completion Quality Rule

Work should only be called finished when it is correct, verified, and not knowingly hiding future bugs.

For implementation work:

1. Fix the root cause, not only the symptom.
2. Preserve documented architecture and ownership rules.
3. Do not introduce temporary hacks, silent bypasses, weak validations, or client-side layout patches.
4. Verify the change with the most relevant available tests or checks.
5. If a known bug, risk, or incomplete behavior remains, state it explicitly instead of calling the result ideal or complete.

For regression tests:

1. Passing tests must assert behavior that is intentionally accepted as correct.
2. Failing tests are allowed when they correctly expose unresolved product gaps.
3. Skipped tests must have a documented, honest reason such as missing fixture, missing environment support, or known unresolved gap.
4. Audit-only tests must represent desired contracts, environment checks, security/business gates, or documented current gaps without weakening stable baselines.
5. Do not make tests pass by broadening assertions, accepting broken behavior, converting real failures into meaningless checks, or hiding product gaps.
6. Every test should have a clear expected classification: stable-pass, audit-fail, audit-skip, fixture-skip, or weak-review until corrected.
