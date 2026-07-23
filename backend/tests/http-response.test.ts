import { expect, test } from "vitest";
import { AppError } from "../src/core/errors";
import { readBoundedBody } from "../src/services/http-response";

const tooLarge = () => new AppError("response_too_large", "响应过大", 502);

test("无 Content-Length 时仍按实际流大小停止读取", async () => {
  const response = new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(4));
      controller.enqueue(new Uint8Array(4));
      controller.close();
    },
  }));
  await expect(readBoundedBody(response, 7, tooLarge)).rejects.toMatchObject({
    code: "response_too_large",
  });
});

test("拒绝无效或超过限制的 Content-Length", async () => {
  await expect(readBoundedBody(new Response("x", {
    headers: { "content-length": "not-a-number" },
  }), 8, tooLarge)).rejects.toMatchObject({ code: "response_too_large" });
  await expect(readBoundedBody(new Response("x", {
    headers: { "content-length": "9" },
  }), 8, tooLarge)).rejects.toMatchObject({ code: "response_too_large" });
});
