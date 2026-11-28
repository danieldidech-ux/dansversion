// ILGA profiles generally publish service dates to the month. Merge overlapping
// intervals and exclude gaps when a member left and later returned.
const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
const month = '(?:(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sept?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\.?\\s+)?';
const date = month+'((?:19|20)\\d{2})';
const ranges = new RegExp('\\b'+date+'\\s*(?:[-–—]|to)\\s*(?:(present|current)|'+date+')\\b','gi');
function dateIndex(name,year) {
  return Number(year)*12 + (name ? months.indexOf(name.slice(0,3).toLowerCase()) : 0);
}
export function serviceMonths(periods, now=new Date()) {
  const current=now.getUTCFullYear()*12+now.getUTCMonth();
  const spans=[];
  for (const line of periods) for (const match of line.replace(/(\d{4})\s*[-–—]\s*(?=$|[;,])/g,'$1 - Present').matchAll(ranges)) {
    const start=dateIndex(match[1],match[2]);
    const end=match[3]?current:Math.min(current,dateIndex(match[4],match[5]));
    if (start<=end) spans.push([start,end]);
  }
  if (!spans.length) return null;
  spans.sort((a,b)=>a[0]-b[0]);
  let total=0, previous=0;
  for (const [start,end] of spans) {
    total+=Math.max(0,end-Math.max(start,previous));
    previous=Math.max(previous,end);
  }
  return total;
}
export function tenureValue(periods) {
  const value=serviceMonths(periods);
  const approximate=periods.some(line=>/(^|[;:,\s])(?:19|20)\d{2}\s*[-–—]/.test(line) && !/[a-z]{3,9}\.?\s+(?:19|20)\d{2}\s*[-–—]/i.test(line));
  return {months:approximate && value!==null ? Math.floor(value/12)*12 : value,approximate};
}

// January 2019 appointments straddled the January 9 inauguration. The
// official directory rounds all three starts to January. House Journal,
// January 7 (HJ100152R), and the 101st GA opening-day transcript.
export function oathOrder(member) {
  if (member.url.endsWith('/House/Members/Details/3352')) return -1;
  if (member.url.endsWith('/House/Members/Details/3366')) return 1;
  return 0;
}
