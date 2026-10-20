import test from 'node:test';
import assert from 'node:assert/strict';

test('scope denial precedes ownership transfer',()=>{
  let cancelled=true, transferred=false;
  const reserve=()=>{ if(cancelled) throw new Error('cancelled scope'); return {retired:false}; };
  const reserveBeforeTransfer=transfer=>{
    const child=reserve();
    try { return {child,value:transfer()}; }
    catch(error) { child.retired=true; throw error; }
  };
  assert.throws(()=>reserveBeforeTransfer(()=>{ transferred=true; return 'owned'; }),/cancelled scope/);
  assert.equal(transferred,false);
});

test('failed transfer preparation retires reserved ticket',()=>{
  let child;
  const reserve=()=>child={retired:false};
  const reserveBeforeTransfer=transfer=>{
    const ticket=reserve();
    try { return transfer(); }
    catch(error) { ticket.retired=true; throw error; }
  };
  assert.throws(()=>reserveBeforeTransfer(()=>{ throw new Error('projection failed'); }),/projection failed/);
  assert.equal(child.retired,true);
});

test('cancellation is not physical completion',()=>{
  let cancellationRequested=true, physicallyRunning=true, released=false;
  const maybeRelease=()=>{ if(cancellationRequested && !physicallyRunning) released=true; };
  maybeRelease(); assert.equal(released,false);
  physicallyRunning=false; maybeRelease(); assert.equal(released,true);
});

// trigger after workflow exists


test('joined proof is consumable only at the exact Task boundary',()=>{
  const exact={kind:'TaskExpr'};
  const lookalike={kind:'TaskExpr'};
  const nonTask={kind:'LiteralExpr'};
  const joined=new Map([[exact,[{name:'x',ownership:'UNIQUE_MOVE'}]]]);

  const requireFor=boundary=>{
    if(boundary.kind!=='TaskExpr') throw new Error('TaskExpr boundary required');
    const proof=joined.get(boundary);
    if(!proof) throw new Error('exact joined admission proof required');
    return proof;
  };

  assert.equal(requireFor(exact).length,1);
  assert.throws(()=>requireFor(lookalike),/exact joined/);
  assert.throws(()=>requireFor(nonTask),/TaskExpr boundary/);
});
