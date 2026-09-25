// Kit example: answers /health with "ok" and / with a greeting, the deployed commit, and the
// database time, which proves the web service reached its Postgres through compose.
const http = require("node:http");
const { Pool } = require("pg");

const port = Number(process.env.PORT || process.env.APP_PORT || 3000);
const sha = process.env.GIT_SHA || "dev";
const pool = process.env.DATABASE_URL ? new Pool({ connectionString: process.env.DATABASE_URL }) : null;

async function dbTime() {
  if (!pool) return "no database configured";
  try {
    const { rows } = await pool.query("select now() as t");
    return rows[0].t.toISOString();
  } catch (err) {
    return `database error (${err.code || err.message})`;
  }
}

http
  .createServer(async (req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("ok\n");
      return;
    }
    if (req.url === "/") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end(`hello from the docker box\nsha: ${sha}\ndb time: ${await dbTime()}\n`);
      return;
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found\n");
  })
  .listen(port, "0.0.0.0", () => console.log(`listening on ${port}`));
