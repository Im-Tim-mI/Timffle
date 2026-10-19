// A stand-in for GitHub's release downloads, for the browser tests (nothing here ever reaches the real GitHub).
//
// The extension downloads the helper's installers from
//   https://github.com/Im-Tim-mI/Timffle-Helper/releases/download/<tag>/<file>
// which GitHub answers with a redirect to its asset host, which answers with the file as an attachment:
//   https://release-assets.githubusercontent.com/...  (Content-Disposition: attachment; filename=<file>)
// This server does the same over TLS with a throw-away certificate. The test browser is started with `args`:
// --host-resolver-rules sends both host names here and --ignore-certificate-errors accepts the certificate.
// A browser started without them would talk to the real GitHub, so the tests always pass them.
import https from 'node:https';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

/**
 * @param dir where the certificate is kept (a new directory of the test run)
 * @param options.status what github.com answers for a release file: 200 serves it, 404 is "Page not found"
 * @returns {port, requests, args, setStatus, close}; `requests` lists every request seen, in order; `setStatus` changes
 *   what github.com answers from then on
 */
export async function startFakeGitHub(dir, {status: initial = 200} = {}) {
  let status = initial;
  await fs.mkdir(dir, {recursive: true});
  const key = path.join(dir, 'key.pem'), cert = path.join(dir, 'cert.pem');
  try {
    await fs.access(cert);
  } catch {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, '-days', '3', '-subj', '/CN=github.com',
      '-addext', 'subjectAltName=DNS:github.com,DNS:release-assets.githubusercontent.com'], {stdio: 'ignore'});
  }
  const requests = [];
  const server = https.createServer({key: await fs.readFile(key), cert: await fs.readFile(cert)}, (req, res) => {
    const host = (req.headers.host || '').split(':')[0];
    requests.push({host, url: req.url, cookie: req.headers.cookie, at: Date.now()});
    if (host === 'github.com') {
      const m = req.url.match(/^\/Im-Tim-mI\/Timffle-Helper\/releases\/download\/([^/]+)\/([^/?]+)$/);
      if (!m || status !== 200) {
        res.writeHead(m ? status : 404, {'Content-Type': 'text/html'});
        res.end('<!doctype html><title>Page not found</title>404');
        return;
      }
      res.writeHead(302, {Location: `https://release-assets.githubusercontent.com/github-production-release-asset/1/${m[2]}?tag=${m[1]}`});
      res.end();
      return;
    }
    if (host === 'release-assets.githubusercontent.com') {
      const name = decodeURIComponent(req.url.split('?')[0].split('/').pop());
      const body = Buffer.from('fake installer ' + name);
      res.writeHead(200, {'Content-Type': 'application/octet-stream', 'Content-Length': body.length, 'Content-Disposition': `attachment; filename=${name}`});
      res.end(body);
      return;
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  return {
    port,
    requests,
    setStatus: (value) => { status = value; },
    args: [`--host-resolver-rules=MAP github.com 127.0.0.1:${port},MAP release-assets.githubusercontent.com 127.0.0.1:${port}`, '--ignore-certificate-errors'],
    close: () => new Promise((resolve) => { server.closeAllConnections?.(); server.close(resolve); }),
  };
}
