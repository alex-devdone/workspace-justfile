// A queue worker still wants a port. It is what makes the process visible to
// kill-port, and what lets two checkouts run side by side.
import { createServer } from 'node:http'
import { basename } from 'node:path'

const flag = process.argv.indexOf('--port')
const port = flag === -1 ? 8085 : Number(process.argv[flag + 1])
const checkout = basename(process.cwd())
let done = 0

createServer((_req, res) => res.end(`${checkout} ok, ${done} jobs\n`)).listen(port, '127.0.0.1', () => {
  console.log(`[worker] ${checkout} · health on http://127.0.0.1:${port}`)
})

setInterval(() => console.log(`[worker] ${checkout} processed job ${++done}`), 3000)
