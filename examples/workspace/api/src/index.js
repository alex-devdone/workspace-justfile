// Stand-in for a real TypeScript service: zero dependencies, so the example
// runs offline. It reports which checkout it came from, which is what makes
// the worktree behaviour visible — curl :8080 and :8081 and compare.
import { createServer } from 'node:http'
import { basename } from 'node:path'

const flag = process.argv.indexOf('--port')
const port = flag === -1 ? 8080 : Number(process.argv[flag + 1])
const checkout = basename(process.cwd())

createServer((_req, res) => {
  res.setHeader('content-type', 'application/json')
  res.end(JSON.stringify({ service: 'api', checkout, port }, null, 2) + '\n')
}).listen(port, '127.0.0.1', () => {
  console.log(`[api] ${checkout} · http://127.0.0.1:${port}`)
})
