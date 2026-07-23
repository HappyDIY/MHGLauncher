import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { contractResponseSchemas, localApiEndpoints } from "../src/api/local-api-contract";
import { contractRequestSchemas } from "../src/api/request-contracts";

type ContractFixture = {
  name: string;
  schema?: keyof typeof contractRequestSchemas;
  model?: keyof typeof contractResponseSchemas;
  body: unknown;
};

type ContractCorpus = {
  version: number;
  endpoints: [string, string][];
  requests: ContractFixture[];
  responses: ContractFixture[];
};

const corpus = JSON.parse(readFileSync(
  join(process.cwd(), "../contracts/local-api/v1/corpus.json"),
  "utf8",
)) as ContractCorpus;

describe("本地 API v1 契约", () => {
  test("端点清单与后端公开端点完全一致", () => {
    const expected = localApiEndpoints.map(([method, path]) => `${method} ${path}`).sort();
    const committed = corpus.endpoints.map(([method, path]) => `${method} ${path}`).sort();
    expect(corpus.version).toBe(1);
    expect(committed).toEqual(expected);
  });

  test.each(corpus.requests)("$name 请求通过实际 Zod 契约", ({ schema, body }) => {
    expect(schema).toBeDefined();
    expect(contractRequestSchemas[schema!].safeParse(body).success).toBe(true);
  });

  test.each(corpus.responses)("$name 响应通过实际响应契约", ({ model, body }) => {
    expect(model).toBeDefined();
    expect(contractResponseSchemas[model!].safeParse(body).success).toBe(true);
  });

  test("请求字段漂移会被拒绝", () => {
    const fixture = corpus.requests.find(({ name }) => name === "update_job")!;
    const invalid = { ...(fixture.body as object), kind: "install-broken" };
    expect(contractRequestSchemas.start_job.safeParse(invalid).success).toBe(false);
  });

  test("响应枚举漂移会被拒绝", () => {
    const fixture = corpus.responses.find(({ name }) => name === "game_job")!;
    const invalid = { ...(fixture.body as object), status: "finished" };
    expect(contractResponseSchemas.game_job.safeParse(invalid).success).toBe(false);
  });
});
