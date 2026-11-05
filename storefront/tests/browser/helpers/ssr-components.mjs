import { readFileSync } from 'node:fs';
import { registerHooks } from 'node:module';
import ts from 'typescript';
await import('../../support/ts-resolver.mjs');

// Load actual TSX/CSS-module imports for server rendering in this test process.
// No application loader, build rule or runtime source is modified.
registerHooks({ load(url, context, next) {
  if (url.endsWith('.module.css')) {
    const css = readFileSync(new URL(url), 'utf8');
    const names = [...css.matchAll(/\.([a-zA-Z_][\w-]*)/g)].map(match => match[1]);
    return { format: 'module', shortCircuit: true, source: `export default ${JSON.stringify(Object.fromEntries(names.map(name => [name, name])))}` };
  }
  if (url.endsWith('.tsx')) return { format: 'module', shortCircuit: true, source: ts.transpileModule(readFileSync(new URL(url), 'utf8'), {
    compilerOptions: { jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext }, fileName: new URL(url).pathname,
  }).outputText };
  return next(url, context);
} });
