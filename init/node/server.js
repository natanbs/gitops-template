const http = require("http");
const port = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  if (req.url === "/healthz" || req.url === "/readyz") {
    res.writeHead(200);
    return res.end("ok");
  }
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Hello from Node.js!");
});
server.listen(port, () => console.log(`Listening on ${port}`));