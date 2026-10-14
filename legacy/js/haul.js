/* =====================================================================
   Arbor Simulator · haul.js
   Hitching the chipper, the truck and chipper as solid shapes for logs
   (so wood can be stacked in the bed and rides along), carrying several
   pieces at once, and sawdust that piles up where you cut.
   ===================================================================== */
'use strict';

const lb=kg=>`${Math.round(kg*2.205)} lb`;
const CARRY_MAX=WOOD.liftMax;       // total weight you can carry at once (kg)

/* ---------- hitch ---------- */
// chip.mode: 'truck' (on the ball), 'free' (parked on its jack), 'hand' (player walking it by the tongue)
function couplerWorld(){return M.apply(chipMatrix(),[0,.5,0]);}
function handHitch(){const p=G.pl,fw=[-Math.sin(p.yaw),0,-Math.cos(p.yaw)];const h=V.add(p.pos,V.mul(fw,.9));h[1]=G.W.H(h[0],h[2])+.58;return h;}
function chipHitchPoint(){return G.chip.mode==='hand'?handHitch():hitchWorld();}
function hitchAction(){const c=G.chip;
  if(c.mode==='truck'){c.mode='free';SFX.clank();toast('Unhitched.',1500);return;}
  if(c.mode==='free'){if(G.pl.carry)dropCarry();c.mode='hand';SFX.pick();return;}
  if(c.mode==='hand'){if(V.dist(couplerWorld(),hitchWorld())<.8){c.mode='truck';settleTrailer(false);SFX.clank();toast('Hitched.',1500);}else{c.mode='free';SFX.drop();}}}
function nearCoupler(){const e=G.eye||V.add(G.pl.pos,[0,1.6,0]);const cp=couplerWorld();const to=V.sub(cp,e),d=V.len(to);return d<2.1&&V.dot(V.norm(to),G.fwd||[0,0,-1])>.72?d:null;}

/* ---------- solid boxes for logs: truck cab, bed floor and walls, chipper body ---------- */
const TRUCK_BOXES=[[[0,1.1,.99],[1.0,.85,1.66]],[[0,.5,-1.69],[.98,.3,.93]],[[-1.0,1.05,-1.69],[.09,.3,.95]],[[1.0,1.05,-1.69],[.09,.3,.95]],[[0,1.0,-2.62],[1.05,.33,.08]],[[0,1.05,-.74],[.98,.28,.04]]];
const CHIP_BOXES=[[[0,1.0,-2.0],[.55,.55,1.0]]];
function boxesFrom(Mx,list){const ax=[V.norm(M.applyDir(Mx,[1,0,0])),V.norm(M.applyDir(Mx,[0,1,0])),V.norm(M.applyDir(Mx,[0,0,1]))];return list.map(([c,h])=>({c:M.apply(Mx,c),ax,h}));}
function updateSolidBoxes(){PHYS.boxes=boxesFrom(truckMatrix(),TRUCK_BOXES).concat(boxesFrom(chipMatrix(),CHIP_BOXES));}
// inside the bed? (truck-local test)
// inverse of a rotation+translation matrix (column-major): rotation transposed, translation −Rᵀt
function invRigid(m){const o=M.ident();
  o[0]=m[0];o[1]=m[4];o[2]=m[8];o[4]=m[1];o[5]=m[5];o[6]=m[9];o[8]=m[2];o[9]=m[6];o[10]=m[10];
  o[12]=-(m[0]*m[12]+m[1]*m[13]+m[2]*m[14]);o[13]=-(m[4]*m[12]+m[5]*m[13]+m[6]*m[14]);o[14]=-(m[8]*m[12]+m[9]*m[13]+m[10]*m[14]);return o;}
function inBed(Minv,p){const l=M.apply(Minv,p);return Math.abs(l[0])<1.2&&l[2]>-2.9&&l[2]<-.6&&l[1]>.6&&l[1]<3;}
// carry whatever is in the bed along with the truck when it moves
function carryBedLoad(Mold,Mnew,dt){const inv=invRigid(Mold);const D=M.mul(Mnew,inv);
  const qD=quatFromBasis(V.norm(M.applyDir(D,[1,0,0])),V.norm(M.applyDir(D,[0,1,0])),V.norm(M.applyDir(D,[0,0,1])));
  for(const b of PHYS.bodies){if(b.mode!=='dyn'||!inBed(inv,b.pos))continue;b.pos=M.apply(D,b.pos);b.v=Q.rot(qD,b.v);b.q=Q.norm(Q.mul(qD,b.q));b.bedRide=true;}}

/* ---------- carrying several pieces ---------- */
function carryMass(){return G.pl.carryList.reduce((s,b)=>s+b.m,0);}
function canAddCarry(b){const L=G.pl.carryList;if(!L.length)return true;if(!!L[0].brush!==!!b.brush)return false;return carryMass()+b.m<=CARRY_MAX;}
function pickUp(b){const p=G.pl;b.mode='held';b.sleep=false;b.still=0;b.holdQ=Q.mul(Q.conj(Q.axis([0,1,0],p.yaw)),b.q);p.carryList.push(b);SFX.pick();}
function dropOne(){const L=G.pl.carryList;const b=L.pop();if(!b)return;releaseBody(b);SFX.drop();setTimeout(updateObjectives,1500);}
function releaseBody(b){b.mode='dyn';b.sleep=false;b.still=0;b.w=[0,0,0];b.v=V.add(V.mul(G.fwd||[0,0,-1],1.0),[0,.5,0]);}
// where each carried piece rides: logs on the right shoulder (stacked), brush in a bundle under the arm
function stepCarry(dt){const p=G.pl,L=p.carryList;if(!L.length)return;const fw=[-Math.sin(p.yaw),0,-Math.cos(p.yaw)],rt=[Math.cos(p.yaw),0,-Math.sin(p.yaw)];
  const eyeY=p.eyeY||1.62;let stackY=0;
  L.forEach((b,i)=>{let np;
    if(b.brush){const {ax:axL,butt}=brushAxis(b);const dir=V.norm(V.add(V.add(V.mul(fw,.8),V.mul(rt,-.55+i*.06)),[0,-.08+i*.03,0]));b.q=orientAxis(b.q,axL,dir,Math.min(1,dt*10));
      const hands=V.add(V.add(V.add(p.pos,[0,1.0+i*.05,0]),V.mul(fw,.5)),V.mul(rt,.22-i*.05));np=V.lerp(b.pos,V.sub(hands,Q.rot(b.q,V.sub(butt,b.com))),Math.min(1,dt*12));}
    else{// over the shoulder: the round's axis runs fore and aft, resting on the right shoulder
      const r=b.piece?G.tree.T.rAt((b.piece.y0+b.piece.y1)/2):.15;const axL=[0,1,0];const dir=V.norm(V.add(fw,[0,.18,0]));b.q=orientAxis(b.q,axL,dir,Math.min(1,dt*10));
      const sh=V.add(V.add(V.add(p.pos,[0,eyeY-.16+r+stackY,0]),V.mul(rt,.3+r*.5)),V.mul(fw,.12));stackY+=r*1.85;
      np=V.lerp(b.pos,sh,Math.min(1,dt*12));}
    b.v=V.mul(V.sub(np,b.pos),1/Math.max(dt,1e-3));b.pos=np;});}

/* ---------- sawdust that settles where you cut ---------- */
const DUST={cells:new Map(),dirty:false,t:0,mesh:null};
function addDust(x,z,amt,chip){const k=Math.round(x/.11)+','+Math.round(z/.11);let c=DUST.cells.get(k);if(!c){if(DUST.cells.size>2500)return;c={x:Math.round(x/.11)*.11,z:Math.round(z/.11)*.11,a:0,chip:!!chip};DUST.cells.set(k,c);}c.a+=amt;DUST.dirty=true;}
function resetDust(){DUST.cells.clear();DUST.dirty=true;}
function dustMesh(){const mb=new MeshB(),H=G.W.H;const saw=hex('#e2cfa0'),chip=hex('#c9a46a');
  for(const c of DUST.cells.values()){const rx=Math.min(.17,.05+Math.sqrt(c.a)*.55),ry=Math.min(.09,.004+c.a*2.2);const j=((c.x*31+c.z*17)%1+1)%1;
    mb.sphere(c.x+(j-.5)*.04,H(c.x,c.z)-ry*.25,c.z+(j-.5)*.04,rx,ry,rx*(.85+j*.3),shade(c.chip?chip:saw,.9+j*.2),7,3);}
  return mb;}
function drawDust(r){if(DUST.dirty&&performance.now()-DUST.t>250){DUST.dirty=false;DUST.t=performance.now();if(DUST.mesh)r.free(DUST.mesh);DUST.mesh=DUST.cells.size?r.upload(dustMesh()):null;}if(DUST.mesh)r.draw(DUST.mesh);}

/* ---------- throwing: a log off the shoulder, into the truck bed if you're near it ---------- */
// is the bed close enough and roughly in front of you to lob something into it?
function throwTarget(){const p=G.pl;if(!G.eye||!G.fwd)return null;const tm=truckMatrix(),inv=invRigid(tm);
  const c=M.apply(tm,[0,1.0,-1.7]);const flat=Math.hypot(c[0]-p.pos[0],c[2]-p.pos[2]);if(flat>6.5)return null;
  const to=V.norm([c[0]-G.eye[0],0,c[2]-G.eye[2]]),fw=V.norm([G.fwd[0],0,G.fwd[2]]);if(!p.onBed&&V.dot(to,fw)<.6)return null;
  // the emptiest spot in the bed (truck-local), nearest the way you're facing on ties
  let best=null;for(const x of [-.45,0,.45])for(const z of [-2.25,-1.75,-1.25]){const w=M.apply(tm,[x,1.0,z]);let crowd=0;
    for(const b of PHYS.bodies){if(b.mode!=='dyn')continue;const l=M.apply(inv,b.pos);if(Math.abs(l[0]-x)<.4&&Math.abs(l[2]-z)<.4)crowd+=1+Math.max(0,l[1]-.8)*3;}
    const score=crowd*10+V.dist(w,V.add(G.eye,V.mul(fw,2)))*.3;if(!best||score<best.score)best={score,x,z,crowd};}
  return M.apply(tm,[best.x,1.05+Math.min(.6,best.crowd*.25),best.z]);}
function throwOne(){const p=G.pl,L=p.carryList;if(!L.length)return;const b=L.pop();const tgt=throwTarget();releaseBody(b);
  if(tgt){// a lob that comes down in the bed: the quickest flight whose arc clears the bed walls with the piece's thickness to spare
    const inv=invRigid(truckMatrix()),r=b.piece&&b.piece.kind==='trunk'?G.tree.T.rAt(b.piece.y0)+.06:.15;const d=V.sub(tgt,b.pos);let tf=1.2;
    for(let t=.4;t<=1.2;t+=.04){let ok=true;for(let i=1;i<20&&ok;i++){const f=i/20;const w=V.add(b.pos,[d[0]*f,d[1]*f+.5*PHYS.g*t*t*f*(1-f),d[2]*f]);const l=M.apply(inv,w);
        const outside=Math.abs(l[0])>.9-r*.3||l[2]<-2.55||l[2]>-.8;if(outside&&Math.abs(l[0])<1.1+r&&l[2]>-2.75-r&&l[2]<-.6+r&&l[1]<1.36+r)ok=false;}
      if(ok){tf=t;break;}}
    b.v=[d[0]/tf,d[1]/tf+.5*PHYS.g*tf,d[2]/tf];}
  else{const fw=[-Math.sin(p.yaw),0,-Math.cos(p.yaw)];b.v=V.add(V.mul(fw,4.2*(1-Math.min(.5,b.m/120))),[0,2.4,0]);}
  b.w=[(Math.random()-.5)*2,(Math.random()-.5)*1,(Math.random()-.5)*2];SFX.pick();setTimeout(updateObjectives,1800);}

/* ---------- dragging: logs too heavy to shoulder but under 200 lb ---------- */
const DRAG_MAX=200/2.205;
function canDrag(b){return !!(b&&b.piece&&b.mode==='dyn'&&b.m>WOOD.liftMax&&b.m<=DRAG_MAX);}
function toggleDrag(){const p=G.pl;if(p.drag){stopDrag();return;}if(p.carry||p.inTruck)return;const a=G.aim;
  if(!a||a.kind!=='body')return;const b=a.b;if(!b.piece)return;
  if(b.m<=WOOD.liftMax){toast('Light enough to pick up (E).',1600);return;}
  if(!canDrag(b)){toast(`Too heavy to drag (${lb(b.m)}). Buck it smaller.`,2200);return;}
  if(p.tool==='saw')equip('hands');
  // grab whichever end is closer to you
  let ends;if(b.piece.kind==='trunk')ends=[[0,b.piece.y0,0],[0,b.piece.y1,0]];else{const {ax,butt}=brushAxis(b);ends=[butt,V.add(butt,V.mul(ax,.6))];}
  const lp=ends.map(e=>V.sub(e,b.com)).sort((u,v)=>V.dist(bodyWorld(b,V.add(u,b.com)),p.pos)-V.dist(bodyWorld(b,V.add(v,b.com)),p.pos))[0];
  p.drag={b,lp};wake(b);SFX.pick();}
function stopDrag(){const p=G.pl;if(!p.drag)return;wake(p.drag.b);p.drag=null;SFX.drop();setTimeout(updateObjectives,1500);}
// a spring from your hands to the grabbed end: the end lifts, the rest drags along the ground
function stepDrag(dt){const p=G.pl,D=p.drag;if(!D)return;const b=D.b;if(b.mode!=='dyn'||!PHYS.bodies.includes(b)){p.drag=null;return;}
  wake(b);const R=M3.fromQ(b.q),r=M3.vec(R,D.lp),gp=V.add(b.pos,r);const fw=[-Math.sin(p.yaw),0,-Math.cos(p.yaw)];
  const rt=[Math.cos(p.yaw),0,-Math.sin(p.yaw)];const tgt=V.add(V.add(V.add(p.pos,V.mul(fw,.45)),V.mul(rt,.42)),[0,.62,0]);const err=V.sub(tgt,gp);   // the end in your right hand, the log trailing behind
  if(Math.hypot(err[0],err[2])>2.4){stopDrag();return;}
  let vdes=V.mul(err,6);const vl=V.len(vdes);if(vl>4)vdes=V.mul(vdes,4/vl);
  const dv=V.sub(vdes,velAt(b,r)),dl=V.len(dv);if(dl<1e-4)return;const n=V.mul(dv,1/dl);const iIw=M3.mul(M3.mul(R,b.iIb),M3.T(R));
  const k=b.im+V.dot(n,V.cross(M3.vec(iIw,V.cross(r,n)),r));let j=dl/k*Math.min(1,dt*14);j=Math.min(j,1150*dt);   // about what a person can pull
  applyImpulse(b,iIw,r,V.mul(n,j));b.w=V.mul(b.w,Math.max(0,1-dt*3));}
