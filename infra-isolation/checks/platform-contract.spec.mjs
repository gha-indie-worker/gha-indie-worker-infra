import assert from "node:assert/strict";
import test from "node:test";
import { resolve } from "node:path";
import { checkPlatformContract } from "../../scripts/check-platform-contract.mjs";

test("indiebuild.dev edge and Cloud Run platform contract is closed over the requested topology", () => {
  const root = resolve(import.meta.dirname, "../..");
  assert.deepEqual(checkPlatformContract(root), []);
});
