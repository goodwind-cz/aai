// Pure production release transform, shared by release finish and PR dry-run.
function fail(causeName, message) {
  throw Object.assign(new Error(message), {
    causeName
  });
}
export function rollup(source, version) {
  const bom=source.startsWith('\uFEFF')?'\uFEFF':'';
  if(bom)source=source.slice(1);
  const newline=source.endsWith('\n');
  const lines=source.split('\n');
  if(newline)lines.pop();
  const first=lines.findIndex(l=>/^## \[/.test(l));
  if(first<0)fail('empty-notes','No rollable entries');
  const cr=lines[first].endsWith('\r')?'\r':'';
  const heads=[];
  for(let i=first;
  i<lines.length;
  i++)if(/^## /.test(lines[i]))heads.push(i);
  heads.push(lines.length);
  const sections=[];
  for(let k=0;
  k<heads.length-1;
  k++) {
    const text=lines.slice(heads[k],heads[k+1]);
    const heading=text[0];
    if(/^## \[unreleased\]/.test(heading)) {
      if(/^## \[unreleased\]\s*$/.test(heading)&&text.slice(1).every(l=>!l.trim()))continue;
      if(!/^## \[unreleased\] — \S/.test(heading)||!text.slice(1).some(l=>l.trim()))fail('malformed-notes','Malformed or empty unreleased entry');
      sections.push({
        entry:true,text:[heading.replace('[unreleased]',`[${version}]`),...text.slice(1)]
      });
    }
    else sections.push({
      entry:false,text
    });
  }
  if(!sections.some(s=>s.entry))fail('empty-notes','No rollable entries');
  const notes=sections.filter(s=>s.entry).flatMap(s=>s.text).map(l=>l.replace(/\r$/,'')).join('\n').trim();
  const ordered=[...sections.filter(s=>s.entry),...sections.filter(s=>!s.entry)];
  return {
    content:bom+[...lines.slice(0,first),'## [unreleased]'+cr,''+cr,...ordered.flatMap(s=>s.text)].join('\n')+(newline?'\n':''),notes
  };
}
