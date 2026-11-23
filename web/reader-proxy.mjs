// Call from the existing Site Worker; feed credentials are server-only bindings.
const routes = new Map([
  ['range-index','url'], ['summary','url'], ['members','chamber'], ['member-service','url']
]);
export async function handleReaderRequest(request, env, fetchUpstream = fetch) {
  const incoming = new URL(request.url);
  if (!incoming.pathname.startsWith('/api/reader/')) return null;
  const route = incoming.pathname.slice('/api/reader/'.length);
  const key = routes.get(route);
  if (!key) return new Response(null,{status:404});
  if (request.method !== 'GET') return new Response(null,{status:405,headers:{Allow:'GET'}});
  const value = incoming.searchParams.get(key);
  if (!value || value.length > 2500) return new Response(null,{status:400});
  if (!env.ILGA_FEED_ORIGIN || !env.ILGA_FEED_TOKEN) return new Response(null,{status:503});
  const upstream = new URL('/'+route,env.ILGA_FEED_ORIGIN);
  if (upstream.protocol !== 'https:') return new Response(null,{status:503});
  upstream.searchParams.set(key,value);
  if (incoming.searchParams.get('refresh')==='1') upstream.searchParams.set('refresh','1');
  try {
    const response = await fetchUpstream(upstream,{
      redirect:'error',signal:request.signal,headers:{authorization:'Bearer '+env.ILGA_FEED_TOKEN}
    });
    if (!response.ok) return new Response(null,{status:502});
    return new Response(response.body,{headers:{'content-type':'application/json','cache-control':'no-store'}});
  } catch {
    return new Response(null,{status:502});
  }
}
