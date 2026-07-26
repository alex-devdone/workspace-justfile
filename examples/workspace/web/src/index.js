// Stand-in for the Vite app, so the example needs no install and no network.
// Swap the dev script for `vite` in a real repo — it takes `--port` too.
import { createServer } from 'node:http'
import { basename } from 'node:path'

const flag = process.argv.indexOf('--port')
const port = flag === -1 ? 3000 : Number(process.argv[flag + 1])
const checkout = basename(process.cwd())

createServer((_req, res) => {
  res.setHeader('content-type', 'text/html')
  res.end(`<!doctype html><title>${checkout}</title><h1>${checkout}</h1><p>served on :${port}</p>\n`)
}).listen(port, '127.0.0.1', () => {
  console.log(`[web] ${checkout} · http://127.0.0.1:${port}`)
})
