import { createServer } from 'node:http';

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
  const html = await measure(rangeUrl, (body) => {
    const numbers = new Set(
      [...body.matchAll(/DocNum=(\d+)/g)]
        .map((match) => Number(match[1]))
    );

    if (
      numbers.size !== 100 ||
      [...numbers].some((n) => n < 501 || n > 600)
    ) {
      throw new Error('Expected exactly SB0501–SB0600');
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
          rangeUrl
        ).href
      )
    )];

    for (const link of links.slice(0, 3)) {
      await measure(link, (body) => {
        if (
          !/id=["']sponsorDiv["']/i.test(body) ||
          !/Senate Sponsors/i.test(body)
        ) {
          throw new Error('Sponsor section not found');
        }

        return { sponsorSectionPresent: true };
      });
    }
  }

  report.state =
    report.results.length === 4 &&
    report.results.every((result) => result.ok)
      ? 'passed'
      : 'failed';

  report.finishedAt = new Date().toISOString();
  console.log(JSON.stringify(report));
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
