# Project Rules

## Frappe Server Scripts — RestrictedPython Constraints

Frappe Server Scripts run under RestrictedPython (`safe_exec`). The following constraints MUST be followed. Violations cause runtime `NameError`, `SyntaxError`, or `ImportError` with no compile-time warning.

### Hard rules

1. **No underscore-prefixed variables.** `_foo`, `_IMAGE_RE`, `__bar` are all rejected at compile time. Use `foo`, `imageRe`, `bar` instead.

2. **No `import` statements.** `import re`, `from os import path`, etc. are blocked. Use only builtins and the pre-injected `frappe` namespace.

3. **No sibling function calls.** A function defined at module level CANNOT call another function defined at the same level. RestrictedPython compiles each `def` with its own restricted scope that does not include the module namespace.

   Bad (will crash at runtime):
   ```python
   def helper():
       return True

   def main_logic():
       helper()  # NameError: name 'helper' is not defined
   ```

   Good — inline the logic:
   ```python
   def main_logic():
       # helper logic directly here
       pass
   ```

   Good — nest the helper:
   ```python
   def main_logic():
       def helper():
           return True
       helper()  # works
   ```

4. **No double-underscore attribute access.** `obj.__class__`, `obj.__dict__`, etc. are blocked.

5. **No `exec()`, `eval()`, `compile()`, `__import__()`.** All blocked.

### Patterns to use instead

- **Regex:** Use `.endswith(tuple)`, `.startswith()`, `in` checks instead of `re`.
- **Helper functions:** Inline them at the call site, or nest them inside the calling function.
- **Constants:** Define at module level (this works), but reference them only from module-level code, not from inside `def` bodies (pass as arguments if needed).
- **Shared logic across scripts:** Duplicate it. Each Server Script is an isolated execution unit; there is no module system.

### Before deploying any server script

Mentally check every `def` body: does it reference anything defined outside that `def`? If so, it will fail. The only names available inside a `def` are: its own locals, its parameters, builtins, and `frappe`.
