import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { rootCertificates, setDefaultCACertificates } from 'node:tls';

// ILGA omits this public intermediate from its TLS handshake. Verify it
// against Node's existing trusted roots before supplying the missing chain.
const issuerPem = readFileSync(new URL('./sectigo-ovr40.pem', import.meta.url), 'utf8');
const issuer = new X509Certificate(issuerPem);
const trustedIssuer = rootCertificates.map((pem) => new X509Certificate(pem))
  .some((root) => root.subject === issuer.issuer && issuer.verify(root.publicKey));
if (!issuer.ca || !trustedIssuer || Date.now() < Date.parse(issuer.validFrom) || Date.now() > Date.parse(issuer.validTo)) {
  throw new Error('ILGA intermediate does not chain to an existing trusted root');
}
setDefaultCACertificates([...rootCertificates, issuerPem]);

async function inspectCertificate() {
  const output = await new Promise((resolve) => {
    const child = execFile('openssl', ['s_client', '-connect', 'ilga.gov:443', '-servername', 'ilga.gov', '-showcerts', '-verify_return_error'],
      { timeout: 10000, maxBuffer: 100000 }, (error, stdout, stderr) => resolve({ stdout, stderr, error: error?.code }));
    child.stdin.end();
  });
  const certificates = [...output.stdout.matchAll(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g)].map(([pem]) => {
    const cert = new X509Certificate(pem);
    return { subject: cert.subject, issuer: cert.issuer, infoAccess: cert.infoAccess, fingerprint: cert.fingerprint256, validTo: cert.validTo };
  });
  return { certificates, verification: output.stderr.slice(-2000) };
}

// Connection diagnostic only. No proxy, external reader, or TLS override.
const rangeUrl = 'https://ilga.gov/Legislation/RegularSession/SB?DocTypeID=SB&GaId=18&SessionId=114&num1=0501&num2=0600';
const report = {
  state: 'running',
  startedAt: new Date().toISOString(),
  results: [],
};

async function officialHtml(input) {
  let url = new URL(input);
  const signal = AbortSignal.timeout(15000);

  for (let redirects = 0; redirects <= 4; redirects++) {
    if (
      url.protocol !== 'https:' ||
      !['ilga.gov', 'www.ilga.gov'].includes(url.hostname) ||
      url.username ||
      url.password ||
      (url.port && url.port !== '443')
    ) {
      throw new Error('Non-ILGA redirect rejected');
    }

    const response = await fetch(url, {
      signal,
      redirect: 'manual',
      headers: {
        accept: 'text/html',
        'user-agent': 'DansVersion-ILGA-Connection-Test/1.0',
        'cache-control': 'no-cache',
      },
    });

    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get('location');
      await response.body?.cancel();
      if (!location) throw new Error('Missing redirect location');
      url = new URL(location, url);
      continue;
    }

    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`HTTP ${response.status}`);
    }

    if (!response.headers.get('content-type')?.includes('text/html')) {
      await response.body?.cancel();
      throw new Error('Expected HTML');
    }

    return await response.text();
  }

  throw new Error('Too many redirects');
}

async function measure(url, inspect) {
  const started = Date.now();

  try {
    const html = await officialHtml(url);
    const details = inspect(html);
    report.results.push({
      url,
      ok: true,
      elapsedMs: Date.now() - started,
      ...details,
    });
    return html;
  } catch (error) {
    report.results.push({
      url,
      ok: false,
      elapsedMs: Date.now() - started,
      error: error.cause?.code || error.code || error.message,
    });
    return null;
  }
}

async function probe() {
  for (const type of ['SB', 'HB']) {
  const currentRange = rangeUrl.replaceAll('SB', type);
  const html = await measure(currentRange, (body) => {
    const numbers = new Set(
      [...body.matchAll(/DocNum=(\d+)/g)]
        .map((match) => Number(match[1]))
    );

    if (
      numbers.size !== 100 ||
      [...numbers].some((n) => n < 501 || n > 600)
    ) {
      throw new Error(`Expected exactly ${type}0501–${type}0600`);
    }

    return { billCount: numbers.size };
  });

  if (html) {
    const links = [...new Set(
      [...html.matchAll(
        /href="([^"]*\/Legislation\/BillStatus\?[^"]+)"/gi
      )].map((match) =>
        new URL(
          match[1].replaceAll('&amp;', '&'),
          currentRange
        ).href
      )
    )];

    for (const link of links) {
      await measure(link, (body) => {
        const clean = (value) => String(value || '').replace(/<[^>]*>/g, '').replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').trim();
        const tab = body.slice(body.indexOf('class="tab-content'));
        const title = clean(tab.match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i)?.[1]);
        const sponsorBlock = body.match(/id=["']sponsorDiv["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
        if (!sponsorBlock || !title) throw new Error('Title or sponsor section not found');
        const sponsor = (chamber) => clean(sponsorBlock.match(new RegExp(`<a\\b[^>]*href=["'][^"']*\\/${chamber}\\/Members\\/Details\\/[^"']+["'][^>]*>([\\s\\S]*?)<\\/a>`, 'i'))?.[1]);
        const senateSponsor = sponsor('Senate');
        const houseSponsor = sponsor('House');
        if (!(type === 'SB' ? senateSponsor : houseSponsor)) throw new Error('Originating sponsor not found');
        return { title, senateSponsor, houseSponsor, retrievedAt: new Date().toISOString() };
      });
    }
  }
  }

  report.state =
    report.results.length === 202 &&
    report.results.every((result) => result.ok)
      ? 'passed'
      : 'failed';

  report.finishedAt = new Date().toISOString();
  if (report.state === 'failed') report.certificateDiagnostic = await inspectCertificate();
  console.log(JSON.stringify({ state: report.state, startedAt: report.startedAt, finishedAt: report.finishedAt, checked: report.results.length, failures: report.results.filter((result) => !result.ok) }));
}

const server = createServer((req, res) => {
  if (
    req.method !== 'GET' ||
    !['/health', '/probe'].includes(req.url)
  ) {
    res.writeHead(404);
    res.end();
    return;
  }

  res.writeHead(200, {
    'content-type': 'application/json',
    'cache-control': 'no-store',
  });

  res.end(JSON.stringify(
    req.url === '/health' ? { status: 'ok' } : report
  ));
});

server.listen(
  Number(process.env.PORT || 10000),
  '0.0.0.0',
  () => { void probe(); }
);

process.on('SIGTERM', () =>
  server.close(() => process.exit(0))
);
