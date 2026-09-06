#!/usr/bin/env node
// Offline verifier for neon/ desired state.
//
// Validates config.json and every projects/*.json against the schemas in
// neon/schema/, then checks the invariants a schema cannot express — including
// agreement with infra-isolation/contract.json.
//
// NO NETWORK. This asserts nothing about the real Neon projects; it asserts that
// what this repository CLAIMS is internally consistent. A green run here plus a
// green infra-isolation run still does not establish deployed isolation.
//
// Dependency-free: node >= 22, standard library only.
//
//   node neon/scripts/verify-neon-state.mjs            # exit 0 clean, 1 findings
//   node neon/scripts/verify-neon-state.mjs --json     # machine-readable

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const neonDir = resolve(here, '..');
const repoRoot = resolve(neonDir, '..');

// ---------------------------------------------------------------------------
// A small JSON Schema validator (the draft-07 subset these schemas use).
// ---------------------------------------------------------------------------

const TYPE_CHECKS = {
  object: v => v !== null && typeof v === 'object' && !Array.isArray(v),
  array: Array.isArray,
  string: v => typeof v === 'string',
  boolean: v => typeof v === 'boolean',
  number: v => typeof v === 'number',
  integer: v => Number.isInteger(v),
  null: v => v === null,
};

function deref(schema, root, depth = 0) {
  if (depth > 32) throw new Error('$ref cycle');
  if (schema && typeof schema === 'object' && typeof schema.$ref === 'string') {
    const ref = schema.$ref;
    if (!ref.startsWith('#/')) throw new Error(`unsupported $ref: ${ref}`);
    let node = root;
    for (const part of ref.slice(2).split('/')) node = node?.[part];
    if (node === undefined) throw new Error(`unresolvable $ref: ${ref}`);
    return deref(node, root, depth + 1);
  }
  return schema;
}

function validate(value, rawSchema, root, path, out) {
  const schema = deref(rawSchema, root);
  if (schema === true) return out;
  if (schema === false) { out.push(`${path}: no value is allowed here`); return out; }

  if (schema.type !== undefined) {
    const names = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!names.some(n => TYPE_CHECKS[n]?.(value))) {
      out.push(`${path}: expected ${names.join('|')}, got ${value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value}`);
      return out;
    }
  }
  if (schema.const !== undefined && value !== schema.const) out.push(`${path}: must be ${JSON.stringify(schema.const)}`);
  if (schema.enum !== undefined && !schema.enum.includes(value)) {
    out.push(`${path}: ${JSON.stringify(value)} is not one of ${JSON.stringify(schema.enum)}`);
  }

  if (typeof value === 'string') {
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) out.push(`${path}: ${JSON.stringify(value)} does not match /${schema.pattern}/`);
    if (schema.minLength !== undefined && value.length < schema.minLength) out.push(`${path}: shorter than ${schema.minLength}`);
    if (schema.maxLength !== undefined && value.length > schema.maxLength) out.push(`${path}: longer than ${schema.maxLength}`);
  }

  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) out.push(`${path}: fewer than ${schema.minItems} items`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems) out.push(`${path}: more than ${schema.maxItems} items`);
    if (schema.uniqueItems) {
      const seen = value.map(v => JSON.stringify(v));
      if (new Set(seen).size !== seen.length) out.push(`${path}: items are not unique`);
    }
    if (schema.items) value.forEach((item, i) => validate(item, schema.items, root, `${path}[${i}]`, out));
  }

  if (TYPE_CHECKS.object(value)) {
    for (const name of schema.required ?? []) {
      if (!(name in value)) out.push(`${path}: missing required property "${name}"`);
    }
    for (const [name, sub] of Object.entries(value)) {
      const propSchema = schema.properties?.[name];
      if (propSchema !== undefined) {
        validate(sub, propSchema, root, `${path}.${name}`, out);
      } else if (schema.additionalProperties === false) {
        out.push(`${path}: unexpected property "${name}"`);
      } else if (schema.additionalProperties && typeof schema.additionalProperties === 'object') {
        validate(sub, schema.additionalProperties, root, `${path}.${name}`, out);
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------

const read = rel => JSON.parse(readFileSync(resolve(neonDir, rel), 'utf8'));
const findings = [];
const fail = (code, detail) => findings.push({ code, detail });

const orgSchema = read('schema/neon-org.schema.json');
const projectSchema = read('schema/neon-project.schema.json');

const config = read('config.json');
for (const e of validate(config, orgSchema, orgSchema, 'config.json', [])) fail('SCHEMA', e);

const projects = {};
for (const [role, rel] of Object.entries(config.projects ?? {})) {
  let doc;
  try {
    doc = read(rel);
  } catch (err) {
    fail('UNREADABLE', `${rel}: ${err.message}`);
    continue;
  }
  projects[role] = doc;
  for (const e of validate(doc, projectSchema, projectSchema, rel, [])) fail('SCHEMA', e);
}

// ---- invariants a schema cannot state -------------------------------------

for (const [role, doc] of Object.entries(projects)) {
  if (doc.role !== role) fail('ROLE_MISMATCH', `${role}: file declares role "${doc.role}"`);
  if (doc.orgId !== config.orgId) fail('ORG_MISMATCH', `${role}: orgId ${doc.orgId} != ${config.orgId}`);
  if (doc.region !== config.defaultRegion) {
    fail('REGION_MISMATCH', `${role}: region ${doc.region} != defaultRegion ${config.defaultRegion}`);
  }
  if (config.expectedState === 'paused' && doc.autoResume === true) {
    // Neon suspension alone wakes on traffic; a paused fleet must prove compute
    // is actually disabled.
    fail('PAUSE_STATE', `${role}: autoResume must be false while the fleet is paused`);
  }
  if (doc.status === 'blocked' && !doc.blockedReason) {
    fail('UNEXPLAINED_BLOCK', `${role}: status is blocked with no blockedReason`);
  }
  // Private networking off but VPC connections allowed would mean the project is
  // reachable over a path that does not exist.
  if (!doc.network.privateNetworking.enabled && doc.network.vpcConnectionsBlocked === false && doc.network.publicConnectionsBlocked === true) {
    fail('UNREACHABLE_BY_DESIGN', `${role}: public blocked and VPC allowed, but no private endpoint exists`);
  }
  if (!doc.network.privateNetworking.enabled && !doc.network.privateNetworking.blockedReason) {
    fail('UNEXPLAINED_NO_PRIVATE_NETWORKING', `${role}: privateNetworking disabled with no blockedReason`);
  }
  const ids = doc.network.privateNetworking.endpointIds ?? [];
  for (const id of ids) {
    // Neon compute endpoints (ep-...) are not AWS VPC endpoints (vpce-...).
    // The isolation contract wants the latter.
    if (id.startsWith('ep-')) fail('COMPUTE_ENDPOINT_AS_VPC_ENDPOINT', `${role}: ${id} is a Neon compute endpoint, not a VPC endpoint`);
  }
  const branchNames = doc.branches.map(b => b.name);
  if (doc.branches.filter(b => b.default).length !== 1) fail('DEFAULT_BRANCH', `${role}: exactly one branch must be default`);
  for (const r of doc.roles) {
    for (const b of r.branches ?? []) {
      if (!branchNames.includes(b)) fail('UNKNOWN_BRANCH', `${role}: role ${r.name} references branch "${b}"`);
    }
    if (r.access === 'owner' && r.secretRef) {
      // DDL belongs to dpm, run by a human. An owner credential handed to a
      // service is a service that can run migrations.
      fail('OWNER_HAS_SECRET', `${role}: owner role ${r.name} must not have a secretRef`);
    }
  }
  const owners = new Set(doc.roles.map(r => r.name));
  for (const db of doc.databases) {
    if (!owners.has(db.owner)) fail('UNKNOWN_OWNER', `${role}: database ${db.name} is owned by unknown role "${db.owner}"`);
  }
}

// The admin project's whole point: it accepts nothing until a private endpoint
// exists. This is the assertion that keeps a well-meaning "fix" visible.
const admin = projects.admin;
if (admin) {
  if (!admin.network.privateNetworking.enabled) {
    if (!admin.network.publicConnectionsBlocked || !admin.network.vpcConnectionsBlocked) {
      fail('ADMIN_NOT_FAIL_CLOSED',
        'admin: with no private endpoint, BOTH publicConnectionsBlocked and vpcConnectionsBlocked must be true. ' +
        'The admin database refusing every connection is the intended state, not an outage.');
    }
  }
}

// Project ids must be distinct: two roles sharing one project is exactly the
// failure the isolation contract exists to catch.
const seenIds = new Map();
for (const [role, doc] of Object.entries(projects)) {
  if (!doc.projectId) continue;
  if (seenIds.has(doc.projectId)) fail('SHARED_PROJECT', `${role} and ${seenIds.get(doc.projectId)} share project ${doc.projectId}`);
  seenIds.set(doc.projectId, role);
}

// ---- agreement with the isolation contract ---------------------------------

try {
  const contract = JSON.parse(readFileSync(resolve(repoRoot, 'infra-isolation/contract.json'), 'utf8'));
  if (contract.mapping?.neonOrg !== config.orgId) {
    fail('CONTRACT_ORG_DRIFT', `infra-isolation contract says neonOrg=${contract.mapping?.neonOrg}, neon/config.json says ${config.orgId}`);
  }
  if (contract.githubOrg !== config.githubOrg) {
    fail('CONTRACT_GITHUB_ORG_DRIFT', `contract githubOrg=${contract.githubOrg}, neon/config.json says ${config.githubOrg}`);
  }
  if (contract.expectedState !== config.expectedState) {
    fail('CONTRACT_STATE_DRIFT', `contract expectedState=${contract.expectedState}, neon/config.json says ${config.expectedState}`);
  }
  for (const entry of contract.projects.filter(p => p.provider === 'neon')) {
    const doc = projects[entry.role];
    if (!doc) { fail('CONTRACT_MISSING_ROLE', `no neon/projects file for role ${entry.role}`); continue; }
    if (entry.projectId !== doc.projectId) {
      fail('CONTRACT_PROJECT_DRIFT', `${entry.role}: contract projectId=${entry.projectId}, neon says ${doc.projectId}`);
    }
    if (entry.region !== doc.region) {
      fail('CONTRACT_REGION_DRIFT', `${entry.role}: contract region=${entry.region}, neon says ${doc.region}`);
    }
  }
} catch (err) {
  fail('CONTRACT_UNREADABLE', `infra-isolation/contract.json: ${err.message}`);
}

// ---- report ----------------------------------------------------------------

const json = process.argv.includes('--json');
if (json) {
  console.log(JSON.stringify({ ok: findings.length === 0, findings }, null, 2));
} else {
  for (const f of findings) console.error(`[neon] ${f.code}: ${f.detail}`);
  console.log(`[neon] ${Object.keys(projects).length} project file(s) checked, ${findings.length} finding(s)`);
  if (findings.length === 0) {
    console.log('[neon] OFFLINE CONSISTENCY ONLY: this says nothing about the real Neon projects.');
  }
}
process.exit(findings.length ? 1 : 0);
