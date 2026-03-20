#!/usr/bin/env node
const fs = require("node:fs");
const http = require("node:http");

const [updatesPath, logPath, portArg] = process.argv.slice(2);
if (!updatesPath || !logPath || !portArg) {
  throw new Error("Usage: fake-telegram-api.js <updates.json> <log.jsonl> <port>");
}

const port = Number(portArg);
let updates = JSON.parse(fs.readFileSync(updatesPath, "utf8"));

function writeLog(entry) {
  fs.appendFileSync(logPath, `${JSON.stringify(entry)}\n`, "utf8");
}

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (chunk) => {
    body += chunk;
  });
  req.on("end", () => {
    const payload = body ? JSON.parse(body) : {};
    if (req.url.includes("/getUpdates")) {
      const offset = Number(payload.offset || 0);
      const result = updates.filter((update) => update.update_id >= offset);
      updates = updates.filter((update) => update.update_id < offset);
      writeLog({ method: "getUpdates", payload, result_count: result.length });
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, result }));
      return;
    }

    if (req.url.includes("/getMe")) {
      writeLog({ method: "getMe", payload });
      res.writeHead(200, { "content-type": "application/json" });
      res.end(
        JSON.stringify({
          ok: true,
          result: {
            id: 777000,
            is_bot: true,
            first_name: "AAI Test Bot",
            username: "aai_test_bot"
          }
        })
      );
      return;
    }

    if (req.url.includes("/sendMessage")) {
      writeLog({ method: "sendMessage", payload });
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, result: { message_id: 1 } }));
      return;
    }

    if (req.url.includes("/answerCallbackQuery")) {
      writeLog({ method: "answerCallbackQuery", payload });
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, result: true }));
      return;
    }

    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: false, result: null }));
  });
});

server.listen(port, "127.0.0.1", () => {
  process.stdout.write(`listening:${port}\n`);
});
