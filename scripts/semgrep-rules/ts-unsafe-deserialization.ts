// Planted-defect fixture for ts-unsafe-deserialization (dimension 2, CWE-502 / CWE-95).
//
// The must-NOT-match lines are enforced coverage: `semgrep test` requires the reported line set to
// equal the annotated set EXACTLY, so an unannotated line that fires fails the test. That is
// load-bearing here for one specific reason -- in js-yaml v4 bare `yaml.load(text)` is SAFE, so a rule
// keyed on the function name would fire on every correct call in every v4 codebase. The `ok` cases
// below are what prevent that.

import yaml from "js-yaml";
import { DEFAULT_FULL_SCHEMA } from "js-yaml";

// These are read from outside the process rather than assigned literals, and that is NOT cosmetic. An
// earlier draft wrote `const userSuppliedExpression = ""`, and `semgrep test` reported the two `eval`
// defects as MISSING: constant propagation resolved the variable to `""`, so the
// `pattern-not: eval("...")` exclusion swallowed them. The fixture's own setup had disabled the rule.
// A fixture that stands in for untrusted input must actually be unresolvable, or it proves the
// opposite of what it claims.
const manifest: string = process.env.MANIFEST_YAML ?? "";
const userSuppliedExpression: string = process.argv[2] ?? "";
const payload: string = process.env.SERIALIZED_PAYLOAD ?? "";

// Opting back into the unsafe schema: this is the defect, not calling `load`.
// ruleid: ts-unsafe-deserialization
export const fullSchemaConfig = yaml.load(manifest, { schema: yaml.DEFAULT_FULL_SCHEMA });

// ruleid: ts-unsafe-deserialization
export const defaultSchemaConfig = yaml.load(manifest, { schema: yaml.DEFAULT_SCHEMA });

// The bare-import spelling of the same thing.
// ruleid: ts-unsafe-deserialization
export const barImportConfig = yaml.load(manifest, { schema: DEFAULT_FULL_SCHEMA });

// Extra keys around the `schema:` key must not stop the match -- this is what the `...` inside the
// object pattern is for.
// ruleid: ts-unsafe-deserialization
export const withExtraOptions = yaml.load(manifest, {
  filename: "config.yaml",
  schema: yaml.DEFAULT_FULL_SCHEMA,
  json: true,
});

// `unserialize` executes embedded functions by design; there is no safe use of it on outside data.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const serializer = require("node-serialize");
// ruleid: ts-unsafe-deserialization
export const revived = serializer.unserialize(payload);

// Code from a string, the direct forms.
// ruleid: ts-unsafe-deserialization
export const computed = eval(userSuppliedExpression);

// ruleid: ts-unsafe-deserialization
export const compiled = new Function(userSuppliedExpression)();

// A literal FIRST argument does not make this safe -- the body is still a variable. Annotated because
// the `pattern-not: new Function("...")` exclusion could plausibly have swallowed it, and measurement
// says it does not.
// ruleid: ts-unsafe-deserialization
export const compiledWithArgs = new Function("a", "b", userSuppliedExpression);

// OK: js-yaml v4's bare `load` uses the core schema and is safe. Must not match -- this is the single
// most important negative case in this fixture, because getting it wrong means a finding on every
// correct call in the ecosystem.
export const safeConfig = yaml.load(manifest);

// OK: an explicitly restricted schema. Must not match.
export const coreSchemaConfig = yaml.load(manifest, { schema: yaml.CORE_SCHEMA });

// OK: JSON. Data in, data out.
export const jsonConfig = JSON.parse(manifest);

// OK: a string literal is not untrusted input. Both of these are excluded by design -- keeping the
// rule pointed at the trust boundary rather than at the function name.
export const constantFolded = eval("2 + 2");
export const trivialFactory = new Function("return 42");

// OK: the documented BLIND SPOT, left UNANNOTATED on purpose. The unsafe schema is real, but it lives
// in a shared options object rather than at the call site, so no call-site pattern can see it. This is
// how the defect usually looks in a codebase that has more than one loader. If a future rule version
// learns to follow the object, `semgrep test` FAILS here and forces the blind-spot list in the .yaml to
// be updated rather than letting it go stale.
const LOADER_OPTIONS = { schema: yaml.DEFAULT_FULL_SCHEMA };
export function loadWithSharedOptions(text: string): unknown {
  return yaml.load(text, LOADER_OPTIONS);
}
