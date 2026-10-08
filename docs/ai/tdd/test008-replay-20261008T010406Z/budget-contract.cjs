const fs=require('fs'),assert=require('assert/strict'),{spawnSync}=require('child_process');
const source=fs.readFileSync(process.argv[2],'utf8');
const outer=source.includes('SHALLOW_REPLAY_TIMEOUT_MS')?Number(source.match(/const NOTE_PROBE_TIMEOUT_MS=(\d+),REPLAY_SETUP_CLEANUP_MS=(\d+)/)[1])+Number(source.match(/const NOTE_PROBE_TIMEOUT_MS=(\d+),REPLAY_SETUP_CLEANUP_MS=(\d+)/)[2]):Number(source.match(/const proof=spawnSync[^\n]+?timeout:(\d+)/)[1]);
const inner=source.includes('NOTE_PROBE_TIMEOUT_MS')?Number(source.match(/const NOTE_PROBE_TIMEOUT_MS=(\d+)/)[1]):Number(source.match(/const noteProbe=spawnSync[^\n]+?timeout:(\d+)/)[1]);
const begin=Date.now(),delayed=spawnSync(process.execPath,['-e',"console.log('PASS: TEST-008 lawful delayed success');setTimeout(()=>process.exit(0),11000)"],{encoding:'utf8',timeout:outer,maxBuffer:65536});
console.log(JSON.stringify({kind:'fixture budget contract, not native cause claim',outer_ms:outer,inner_ms:inner,elapsed_ms:Date.now()-begin,status:delayed.status,signal:delayed.signal,error_code:delayed.error?.code||null,stdout:delayed.stdout}));
assert.equal(delayed.status,0,'lawful completion inside inner budget survives outer replay');assert.equal(delayed.error,undefined);assert.match(delayed.stdout,/PASS: TEST-008/);assert(outer>inner,'outer includes setup and cleanup allowance');
const immediate=spawnSync(process.execPath,['-e','process.exit(0)'],{timeout:outer});assert.equal(immediate.status,0);
const hang=spawnSync(process.execPath,['-e',"console.log('hang reached');setInterval(()=>{},1000)"],{encoding:'utf8',timeout:300,maxBuffer:65536});assert.equal(hang.status,null);assert.equal(hang.error.code,'ETIMEDOUT');assert.match(hang.stdout,/hang reached/);console.log('immediate_exit0=true bounded_hang_ETIMEDOUT=true');
