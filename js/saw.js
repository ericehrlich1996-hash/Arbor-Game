/* =====================================================================
   Arbor Simulator · saw.js
   Free-form cutting. The chainsaw bar is a real segment in the world:
   wherever it enters wood, at whatever angle the player holds it, a cut
   plane is made there and eaten deeper while the throttle is held.
   - Standing tree: cuts are planes in the tree's wood frame. Two cuts that
     meet from the same side free a wedge (an open face). The wood still
     holding the stem to the stump is found by testing a grid of fibre
     columns; when little is left the tree goes over that hinge.
   - Logs and limbs: a cut through the full section splits the piece.
   Mouse wheel rolls the saw (the kerf turns with the bar).
   ===================================================================== */
'use strict';

const SAWC={barL:.61,barBase:-.22,reach:.95,kerf:.015};   // kerf = half the width of the slot the chain removes

/* ---------- quaternion from an orthonormal basis (columns x,y,z) ---------- */
function quatFromBasis(x,y,z){const m00=x[0],m11=y[1],m22=z[2],tr=m00+m11+m22;let q;
  if(tr>0){const s=Math.sqrt(tr+1)*2;q=[(y[2]-z[1])/s,(z[0]-x[2])/s,(x[1]-y[0])/s,.25*s];}
  else if(m00>m11&&m00>m22){const s=Math.sqrt(1+m00-m11-m22)*2;q=[.25*s,(y[0]+x[1])/s,(z[0]+x[2])/s,(y[2]-z[1])/s];}
  else if(m11>m22){const s=Math.sqrt(1+m11-m00-m22)*2;q=[(y[0]+x[1])/s,.25*s,(z[1]+y[2])/s,(z[0]-x[2])/s];}
  else{const s=Math.sqrt(1+m22-m00-m11)*2;q=[(z[0]+x[2])/s,(z[1]+y[2])/s,.25*s,(x[1]-y[0])/s];}
  return Q.norm(q);}
function camWorld(cam){return M.mul(M.mul(M.T(cam.eye[0],cam.eye[1],cam.eye[2]),M.Ry(cam.yaw)),M.mul(M.Rx(cam.pitch),M.Rz(cam.roll||0)));}

/* ---------- saw pose: idle at the hip, engaged with the bar out in front ---------- */
function sawPose(cam,dt){const s=G.saw,p=G.pl;
  const want=(s.on&&G.mouse.r&&!p.carry)?1:0;s.eng=lerp(s.eng||0,want,Math.min(1,dt*9));
  const bob=[Math.sin(p.bob)*.012,-Math.abs(Math.cos(p.bob))*.012];let pullY=0,pullR=0;if(s.pull>0){const k=Math.sin((1-s.pull/.5)*Math.PI);pullY=-.06*k;pullR=.25*k;}
  // idle pose (camera space)
  const iq=Q.mul(Q.mul(Q.mul(Q.axis([0,1,0],.55),Q.axis([1,0,0],.1+pullR)),Q.axis([0,0,1],-.22)),Q.axis([0,0,1],s.roll));
  const ip=[.3+bob[0],-.36+pullY+bob[1],-.42];
  // engaged pose: bar runs out along the line of sight, tip just under the crosshair
  const reach=1+clamp(-cam.pitch,0,1.2)*.5;const tip=[0,-.03,-1.12*reach],f=V.norm(V.sub(tip,[.065,-.17,-.5*reach]));const up0=[0,1,0];   // reach grows as you bend over to look down
  let rgt=V.norm(V.cross(f,up0)),upp=V.cross(rgt,f);                     // camera-ish right/up orthogonal to the bar
  const ax=V.add(V.mul(rgt,Math.cos(s.roll)),V.mul(upp,Math.sin(s.roll)));   // saw's local +X = kerf normal
  const z=V.mul(f,-1),x=ax,y=V.cross(z,x);const eq=quatFromBasis(x,y,z);
  const ep=V.sub(tip,V.mul(f,-SAWC.barBase+SAWC.barL+.0));
  const k=smooth(clamp(s.eng,0,1));let pos=V.lerp(ip,ep,k),q=Q.slerp(iq,eq,k);
  // the bar can't pass through wood: back the saw off to the bark, or to the cut front
  const CW=camWorld(cam);const toW=pt=>M.apply(CW,pt),dirW=d=>V.norm(M.applyDir(CW,d));
  const barB=V.add(pos,Q.rot(q,[0,0,SAWC.barBase])),fC=V.norm(Q.rot(q,[0,0,-1]));
  const B=toW(barB),fW=dirW(fC);s.shift=0;
  if(k>.5){const allowed=s.cut?cutAllowed(s.cut,B,fW):null;let lim=allowed;
    if(lim==null){const h=woodHit(B,fW,SAWC.barL+.3);if(h)lim=h.t;}
    if(lim!=null&&lim<SAWC.barL){s.shift=Math.min(.45,SAWC.barL-lim);pos=V.sub(pos,V.mul(fC,s.shift));}}
  const vib=s.on?(s.cutting?.005:.0022):0;pos=V.add(pos,[(Math.random()-.5)*vib,(Math.random()-.5)*vib,0]);
  s.poseCam=M.QT(q,pos);s.poseW=M.mul(CW,s.poseCam);s.CW=CW;
  s.B=toW(V.add(pos,Q.rot(q,[0,0,SAWC.barBase])));s.T=toW(V.add(pos,Q.rot(q,[0,0,SAWC.barBase-SAWC.barL])));s.f=V.norm(V.sub(s.T,s.B));
  s.n=V.norm(M.applyDir(CW,Q.rot(q,[1,0,0])));s.k=k;}

/* ---------- what wood does the bar line touch? ---------- */
function woodHit(B,f,maxT){let best=null;const tr=G.tree;
  if(tr.state==='stand'){const yb=clamp(B[1]-tr.y0,0,tr.T.cb);const h=rayCapsule(B,f,maxT,[tr.x,tr.y0-.3,tr.z],[tr.x,tr.y0+tr.T.cb,tr.z],tr.T.rAt(yb)+.01);if(h)best={kind:'tree',t:h.t,p:h.p};}
  if(tr.state!=='stand'&&tr.stump){const top=tr.barberDir?tr.stumpY0+1.5:tr.stumpH+.04;const h=rayCapsule(B,f,maxT,[tr.x,tr.y0-.3,tr.z],[tr.x,tr.y0+top,tr.z],tr.T.rAt(.3)+.01);if(h&&(!best||h.t<best.t))best={kind:'stump',t:h.t,p:h.p};}
  const rb=rayBodies(B,f,maxT,b=>b.mode==='dyn'&&b.piece);if(rb&&(!best||rb.t<best.t))best={kind:'body',t:rb.t,p:rb.p,b:rb.b,cap:rb.cap};
  return best;}
// how far along the bar the tip may sit while a cut is in progress
function cutAllowed(c,B,f){const W=cutWorld(c);if(!W)return null;return V.dot(V.sub(W.e,B),f)+c.s;}
function cutWorld(c){if(c.kind==='tree'||c.kind==='stump'){const tr=G.tree,base=[tr.x,tr.y0,tr.z];return {e:V.add(base,Q.rot(tr.q,c.e)),f:Q.rot(tr.q,c.f),n:Q.rot(tr.q,c.n)};}
  const b=c.b;if(!PHYS.bodies.includes(b))return null;return {e:bodyWorld(b,c.e),f:Q.rot(b.q,c.f),n:Q.rot(b.q,c.n)};}

/* ---------- cutting, every frame ---------- */
function stepSaw(dt){const s=G.saw,tr=G.tree;s.cutting=false;s.bind=false;
  if(G.pl.tool!=='saw'||!s.on||G.pl.carry){s.cut=null;return;}
  if(!G.mouse.r||s.k<.96){s.cut=null;return;}
  if(!s.cut){const h=woodHit(s.B,s.f,SAWC.barL+.02);if(!h||h.t>SAWC.barL+.01)return;s.cut=startCut(h);if(!s.cut)return;}
  const c=s.cut,W=cutWorld(c);if(!W){s.cut=null;return;}
  // the saw has to stay in its kerf: turning or rolling it out of line binds the bar
  const aligned=V.dot(s.f,W.f)>.985&&Math.abs(V.dot(s.n,W.n))>.98;
  // fibres must be crossed; a plane running with the grain just skates
  const grain=(c.kind==='tree'||c.kind==='stump')?Q.rot(tr.q,[0,1,0]):c.limb!=null?Q.rot(c.b.q,G.tree.T.limbs[c.limb].dir):Q.rot(c.b.q,[0,1,0]);
  const crosses=Math.abs(V.dot(W.n,grain))>.34;
  s.cutting=true;if(!aligned||!crosses){s.bind=true;return;}
  const rate=WOOD.cutSpeed*(.35+.65*s.rpm)*(c.limb!=null?1.5:1);const maxS=c.exit+.004;
  if(c.s<maxS){c.s=Math.min(maxS,c.s+rate*dt);}
  const front=V.add(W.e,V.mul(W.f,c.s));emit(W.e,V.add(V.mul(W.f,-1.6),[0,.9,0]),5,hex('#e2cfa0'),1.4,1.1,.026);if(Math.random()<.5)emit(W.e,V.add(V.mul(W.f,-1),[0,.3,0]),2,hex('#b89a6a'),.8,1.4,.045);
  if(c.kind==='tree'){tr.cutDirty=true;}
  else if(c.kind==='stump'){if(c.s>=c.exit){finishStumpCut(c);s.cut=null;}}
  else if(c.s>=c.exit){finishPieceCut(c);s.cut=null;}
  else if(c.limb==null&&performance.now()-(c.b.kerfT||0)>90){c.b.kerfT=performance.now();RD.free(c.b.gpu);c.b.gpu=RD.upload(buildPieceMesh(G.tree.T,c.b.piece,null));}}
function startCut(h){const s=G.saw;
  if(h.kind==='stump'){const tr=G.tree,base=[tr.x,tr.y0,tr.z],qi=Q.conj(tr.q);const e=Q.rot(qi,V.sub(h.p,base)),f=Q.rot(qi,s.f),n=Q.rot(qi,s.n);
    for(const c of tr.stumpCuts){if(Math.abs(V.dot(c.n,n))>.995&&Math.abs(V.dot(c.n,V.sub(e,c.e)))<.012&&V.dot(c.f,f)>.97&&!c.done)return c;}
    const c={kind:'stump',e,f,n,s:0,exit:chordTree(e,f)};tr.stumpCuts.push(c);return c;}
  if(h.kind==='tree'){const tr=G.tree,base=[tr.x,tr.y0,tr.z],qi=Q.conj(tr.q);
    const e=Q.rot(qi,V.sub(h.p,base)),f=Q.rot(qi,s.f),n=Q.rot(qi,s.n);
    // continue an existing kerf if the bar is back in it
    for(const c of tr.cuts){if(Math.abs(V.dot(c.n,n))>.995&&Math.abs(V.dot(c.n,V.sub(e,c.e)))<.012&&V.dot(c.f,f)>.97)return c;}
    const c={kind:'tree',e,f,n,s:0,exit:chordTree(e,f)};tr.cuts.push(c);return c;}
  const b=h.b,qi=Q.conj(b.q);const e=bodyLocal(b,h.p),f=Q.rot(qi,s.f),n=Q.rot(qi,s.n);
  const c={kind:'body',b,e,f,n,s:0,limb:h.cap.limb!=null?h.cap.limb:null,sub:h.cap.sub,cap:h.cap};
  // a cut already started on this piece at the same place picks up where it left off
  if(c.limb==null&&b.piece.kerfs){for(const k of b.piece.kerfs){if(Math.abs(V.dot(k.n,n))>.99&&Math.abs(V.dot(k.n,V.sub(e,k.e)))<.015&&V.dot(k.f,f)>.95){k.b=b;k.cap=h.cap;return k;}}}
  // distance through the wood along the bar
  const capW={a:bodyWorld(b,V.add(h.cap.a,b.com)),b:bodyWorld(b,V.add(h.cap.b,b.com)),r:h.cap.r};
  const [tIn,tOut]=chord(t=>{const p=V.add(h.p,V.mul(s.f,t));const [cp]=closestOnSeg(p,capW.a,capW.b);return V.dist(p,cp)<=capW.r;},-.05,1.4);
  if(tIn!=null){c.e=bodyLocal(b,V.add(h.p,V.mul(s.f,tIn)));}c.exit=Math.max(.02,(tOut!=null&&tIn!=null)?tOut-tIn:.05);
  if(c.limb==null&&h.cap.trunk){(b.piece.kerfs=b.piece.kerfs||[]).push(c);}return c;}
// march along a line: first distance inside the wood, and where it leaves again
function chord(inside,t0,t1){let tIn=null,tOut=null;for(let t=t0;t<=t1;t+=.004){const i=inside(t);if(i&&tIn==null)tIn=t;if(!i&&tIn!=null){tOut=t;break;}}if(tIn!=null&&tOut==null)tOut=t1;return [tIn,tOut];}
function chordTree(e,f){const T=G.tree.T;const [a,b]=chord(t=>{const p=V.add(e,V.mul(f,t));return Math.hypot(p[0],p[2])<=T.rAt(clamp(p[1],0,T.H));},-.03,1.5);return a!=null?Math.max(.02,b-Math.max(0,a)):.02;}
function finishPieceCut(c){const b=c.b,P=b.piece,T=G.tree.T;
  if(c.limb!=null){const L=T.limbs[c.limb];const [ta,tb]=limbSpan(P,c.limb);let t;
    if(c.sub!=null)t=L.subs[c.sub].t-.02;   // a side branch comes off with the stretch of limb beyond it
    else{const d=V.dot(c.n,L.dir)*L.len;t=Math.abs(d)>1e-4?V.dot(c.n,V.sub(c.e,L.base))/d:(ta+tb)/2;}
    t=clamp(t,ta,tb);
    if(P.kind==='trunk'){if(t-ta<.06)limbBody(b,c.limb);else if(tb-t>.04)cutLimbAt(b,c.limb,t);}
    else if(t-ta>.03&&tb-t>.03)splitLimbPiece(b,t);
    updateObjectives();return;}
  if(P.kind==='trunk'&&c.cap.trunk){// where the cut plane crosses the stem axis (wood frame)
    const n=c.n,e=c.e;let y=Math.abs(n[1])>1e-3?e[1]+(n[0]*e[0]+n[2]*e[2])/n[1]:e[1];y=clamp(y,P.y0+.02,P.y1-.02);
    if(y-P.y0<.03||P.y1-y<.03)return;buckBody(b,y);updateObjectives();}}
// cleaning up a stump (or a barber chair) after the fall
function finishStumpCut(c){const tr=G.tree,T=tr.T;c.done=true;c.s=c.exit+.01;
  const yc=c.e[1]+(c.n[0]*c.e[0]+c.n[2]*c.e[2])/(Math.abs(c.n[1])>1e-3?c.n[1]:1e-3);   // plane height at the stem centre
  if(tr.barberDir&&yc<tr.stumpY0+1.4){spawnSlab(tr);tr.barberDir=null;}
  if(yc<tr.stumpH){tr.stumpH=Math.max(.02,yc);G.stumpCol=[{x:tr.x,z:tr.z,r:T.rAt(tr.stumpH),y0:tr.y0-2,y1:tr.y0+tr.stumpH}];}
  RD.free(tr.stump);tr.stump=RD.upload(buildStumpMesh2(T,tr.cuts.concat(tr.stumpCuts.filter(k=>k.done)),tr.stumpR,tr.stumpY0,tr.barberDir));SFX.crunch();}
function spawnSlab(tr){const T=tr.T,r=T.rAt(tr.stumpY0),d=tr.barberDir,base=[tr.x,tr.y0,tr.z];
  const c=V.add(base,[-d[0]*r*.55,tr.stumpY0+.75,-d[2]*r*.55]);const w=r*1.3,th=r*.45,hh=1.5;const yaw=Math.atan2(d[0],d[2]);const q=Q.axis([0,1,0],yaw);
  const mb=new MeshB();mb.box(0,0,0,w,hh,th,SAP,[SAP,SAP,SAP,SAP,SAP,BARK]);
  const pts=[];for(const sx of [-1,1])for(const sy of [-1,1])for(const sz of [-1,1])pts.push([sx*w/2,sy*hh/2,sz*th/2]);const m=WOOD.rho*w*hh*th*.7;
  const b=makeBody([{p:[0,0,0],m,I:[m*(hh*hh+th*th)/12,0,0,0,m*(w*w+th*th)/12,0,0,0,m*(w*w+hh*hh)/12]}],pts,[{a:[0,-hh/2+th/2,0],b:[0,hh/2-th/2,0],r:th/2}],q,c,{slab:true});
  b.gpu=RD.upload(mb);b.v=V.mul([-d[0],0,-d[2]],.5);b.w=V.mul(V.cross([0,1,0],[-d[0],0,-d[2]]),.8);PHYS.bodies.push(b);}

/* ---------- standing tree: which fibre columns are still whole? ---------- */
function cutYAt(c,x,z){if(Math.abs(c.n[1])<.05)return null;return c.e[1]-(c.n[0]*(x-c.e[0])+c.n[2]*(z-c.e[2]))/c.n[1];}
function cutSevers(c,x,z){const y=cutYAt(c,x,z);if(y==null)return null;const T=G.tree.T;if(x*x+z*z>T.rAt(clamp(y,0,T.H))**2)return null;
  const d=(x-c.e[0])*c.f[0]+(y-c.e[1])*c.f[1]+(z-c.e[2])*c.f[2];return d<=c.s?y:null;}
function analyzeStanding(){const tr=G.tree,T=tr.T,cuts=tr.cuts.filter(c=>c.s>.004);if(!cuts.length)return null;
  // reference radius at the cut band
  const ys=cuts.map(c=>c.e[1]);const yb=clamp(ys.reduce((a,b)=>a+b,0)/ys.length,0,T.H);const R=T.rAt(yb);
  const N=26,cols=[];let total=0,held=0;
  for(let i=0;i<N;i++)for(let j=0;j<N;j++){const x=(i+.5)/N*2*R-R,z=(j+.5)/N*2*R-R;if(x*x+z*z>R*R)continue;total++;
    let lo=null,hi=null;for(const c of cuts){const y=cutSevers(c,x,z);if(y!=null){lo=lo==null?y:Math.min(lo,y);hi=hi==null?y:Math.max(hi,y);}}
    if(lo==null)held++;cols.push({x,z,lo,hi});}
  // open faces: pairs of cuts from the same side that meet inside the wood
  const wedges=[];for(let a=0;a<cuts.length;a++)for(let b=a+1;b<cuts.length;b++){const w=wedgeOf(cuts[a],cuts[b]);if(w)wedges.push(w);}
  return {R,yb,cols,total,held,frac:held/total,wedges};}
function wedgeOf(c1,c2){const T=G.tree.T;const h1=V.norm([c1.f[0],0,c1.f[2]]),h2=V.norm([c2.f[0],0,c2.f[2]]);if(V.dot(h1,h2)<.5)return null;
  const nd=Math.abs(V.dot(c1.n,c2.n));if(nd>.985)return null;
  const l=V.norm(V.cross(c1.n,c2.n));
  // a point on both planes: solve with the third equation l·p = 0
  const d1=V.dot(c1.n,c1.e),d2=V.dot(c2.n,c2.e);const n1=c1.n,n2=c2.n;
  const p0=V.mul(V.add(V.mul(V.cross(n2,l),d1),V.mul(V.cross(l,n1),d2)),1/V.dot(V.cross(n1,n2),l));
  let inside=0,ok=0;for(let t=-.6;t<=.6;t+=.02){const q=V.add(p0,V.mul(l,t));if(q[1]<0||q[1]>T.H||Math.hypot(q[0],q[2])>T.rAt(q[1])*.97)continue;inside++;
    if(V.dot(V.sub(q,c1.e),c1.f)<=c1.s+.004&&V.dot(V.sub(q,c2.e),c2.f)<=c2.s+.004)ok++;}
  if(inside<3||ok/inside<.85)return null;
  const face=V.norm(V.mul(V.add(h1,h2),-1));
  // the line's horizontal position toward the face → notch depth
  const R=T.rAt(clamp(p0[1],0,T.H));const sp=p0[0]*face[0]+p0[2]*face[2];const depth=R-sp;
  // an interior point of the wedge: between the two entry points, just inside the bark
  const w=V.add(V.mul(V.add(c1.e,c2.e),.5),V.mul(face,-.01));
  return {c1,c2,l,p0,face,depth,angle:Math.acos(nd)*180/Math.PI,s1:Math.sign(V.dot(n1,V.sub(w,p0)))||1,s2:Math.sign(V.dot(n2,V.sub(w,p0)))||1};}
function inWedge(w,p){return Math.sign(V.dot(w.c1.n,V.sub(p,w.p0)))===w.s1&&Math.sign(V.dot(w.c2.n,V.sub(p,w.p0)))===w.s2&&V.dot(V.sub(p,w.p0),w.face)>-.002;}

function stepStanding(dt){const tr=G.tree;if(tr.state!=='stand')return;
  if(tr.cutDirty&&performance.now()-(tr.lastBuild||0)>110){tr.cutDirty=false;tr.lastBuild=performance.now();
    const A=analyzeStanding();tr.A=A;
    // newly opened faces pop their wedge out
    if(A)for(const w of A.wedges){const key=tr.cuts.indexOf(w.c1)+'-'+tr.cuts.indexOf(w.c2);if(!tr.freed[key]){tr.freed[key]=w;spawnWedge(w);}}
    rebuildStanding();
    if(A){const open=Object.keys(tr.freed).length>0;
      if(A.held===0)tr.goKind='drop';else if(open&&A.frac<=.13)tr.goKind='hinge';else if(!open&&A.frac<=.3&&leansOverHold(A))tr.goKind='barber';else if(!open&&A.frac<=.08)tr.goKind='drop';else tr.goKind=null;}}
  if(tr.goKind){tr.goAcc=(tr.goAcc||0)+dt;if(tr.goAcc>.14)startFall(tr.goKind);}else tr.goAcc=0;}
// without an open face, a deep cut from one side lets the stem split up the back
// a barber chair needs real lean, and the stem leaning over the uncut wood that is left holding it
function leansOverHold(A){const tr=G.tree;if(G.W.tree.lean<.035)return false;let sx=0,sz=0,n=0;for(const c of A.cols){if(c.lo==null){sx+=c.x;sz+=c.z;n++;}}if(!n)return false;
  const h=V.norm([sx/n,0,sz/n]);const lw=Q.rot(Q.conj(tr.q),tr.leanDir);return h[0]*lw[0]+h[2]*lw[2]>.45;}

/* ---------- start the fall ---------- */
function startFall(kind){const tr=G.tree,T=tr.T,A=tr.A||analyzeStanding();tr.goKind=null;
  const wedges=Object.values(tr.freed);let face=null,depth=0,angle=0;if(wedges.length){const w=wedges.reduce((a,b)=>a.depth>b.depth?a:b);face=w.face;depth=w.depth;angle=w.angle;}
  // hinge: the columns still holding
  const H=A.cols.filter(c=>c.lo==null);let cx=0,cz=0;for(const c of H){cx+=c.x;cz+=c.z;}if(H.length){cx/=H.length;cz/=H.length;}
  let fd;const lean=tr.leanDir;
  if(kind==='hinge'&&face){let dir=face.slice();
    if(H.length>3){let xx=0,zz=0,xz=0;for(const c of H){const dx=c.x-cx,dz=c.z-cz;xx+=dx*dx;zz+=dz*dz;xz+=dx*dz;}const th=.5*Math.atan2(2*xz,xx-zz);const a=[Math.cos(th),0,Math.sin(th)];
      const l1=(xx+zz)/2+Math.sqrt(((xx-zz)/2)**2+xz*xz),l2=(xx+zz)/2-Math.sqrt(((xx-zz)/2)**2+xz*xz);
      if(l1>2.5*Math.max(l2,1e-9)){const perp=V.sub(dir,V.mul(a,V.dot(dir,a)));if(V.len(perp)>.2)dir=V.norm(perp);}}
    fd=A.frac<.025?V.norm(V.add(V.mul(dir,.6),lean)):dir;}
  else fd=lean.slice();
  // pieces of the stem above the cuts
  let yTop=0,ySum=0,yN=0;for(const c of A.cols){if(c.hi!=null){yTop=Math.max(yTop,c.hi);ySum+=c.hi;yN++;}}const y0=yN?ySum/yN:A.yb;
  // hinge thickness measured along the fall direction
  let hmin=1e9,hmax=-1e9;for(const c of H){const s=c.x*fd[0]+c.z*fd[2];hmin=Math.min(hmin,s);hmax=Math.max(hmax,s);}const hingeT=H.length?hmax-hmin+2*A.R/26:0;
  const D=2*A.R;const err=face?Math.acos(clamp(V.dot(fd,face),-1,1))*180/Math.PI:180;
  tr.grade={notchPct:depth/D,notchAngle:angle,hingePct:hingeT/D,hingeIn:hingeT*39.37,dirErr:err,barber:kind==='barber',open:!!face};
  tr.state='hinge';tr.fd=fd;
  const P={kind:'trunk',y0,y1:T.H,limbs:T.limbs.map(l=>l.id),cutBottom:true,butt:{cuts:tr.cuts.map(c=>Object.assign({},c)),wedges:wedges,hingeY:y0}};const base=[tr.x,tr.y0,tr.z];
  const b=spawnPiece(P,tr.q,base);b.mode='hinge';
  const piv=V.add(base,Q.rot(tr.q,H.length?[cx,y0,cz]:[0,y0,0]));
  tr.hinge={axis:V.norm(V.cross([0,1,0],fd)),P:piv,Pc:V.add(base,[0,y0,0]),th:0,td:kind==='hinge'?.12:.35,q0:b.q.slice(),pos0:b.pos.slice(),body:b,t:0,brk:kind==='hinge'?1.25:.45};
  tr.body=b;RD.free(tr.mesh);tr.mesh=null;tr.stumpH=y0;
  tr.stumpR=A.R;tr.stumpY0=y0;tr.barberDir=kind==='barber'?fd:null;tr.stumpCuts=[];tr.stump=RD.upload(buildStumpMesh2(T,tr.cuts,A.R,y0,tr.barberDir));
  G.stumpCol=[{x:tr.x,z:tr.z,r:T.rAt(y0),y0:tr.y0-2,y1:tr.y0+y0}];
  SFX.creak();setTimeout(()=>SFX.crack(),600);
  shout(kind==='barber'?'BARBER CHAIR!':'TIMBER!');
  if(kind==='barber')omBark("Holy smokes! It split right up the middle!",3500);
  else setTimeout(()=>omBark(['WHOOO-EE! Did ya feel that in your boots?!','Timber! I always wanted to yell that.','Lord, that was louder than my ex-wife.'][Math.floor(Math.random()*3)],3500),2600);
  G.saw.cut=null;}

/* ---------- the notch wedge pops out as its own little piece ---------- */
function spawnWedge(w){const tr=G.tree,T=tr.T,base=[tr.x,tr.y0,tr.z];const R=T.rAt(clamp(w.p0[1],0,T.H));
  const sp=w.p0[0]*w.face[0]+w.p0[2]*w.face[2];const half=Math.sqrt(Math.max(.0004,R*R-sp*sp))*.9;
  const out=(n)=>{let d=V.norm(V.cross(w.l,n));if(V.dot(d,w.face)<0)d=V.mul(d,-1);const hz=Math.hypot(d[0],d[2])||1;return V.add(w.p0,V.mul(d,Math.min(.6,w.depth/hz)));};
  const A=w.p0,B=out(w.c1.n),C=out(w.c2.n);const toW=p=>V.add(base,Q.rot(tr.q,p));
  const P=[];for(const s of [-1,1])for(const p of [A,B,C])P.push(toW(V.add(p,V.mul(w.l,s*half))));
  const mb=new MeshB();const tri=(a,b,c,col)=>{const n=V.norm(V.cross(V.sub(b,a),V.sub(c,a)));const i=mb.v(a,n,col),j=mb.v(b,n,col),k=mb.v(c,n,col);mb.tri(i,j,k);};
  tri(P[0],P[1],P[2],SAP);tri(P[3],P[5],P[4],SAP);mb.face([P[0],P[1],P[4],P[3]],SAP);mb.face([P[0],P[2],P[5],P[3]],SAP);mb.face([P[1],P[2],P[5],P[4]],BARK);
  const cen=V.mul(P.reduce((a,b)=>V.add(a,b),[0,0,0]),1/6);const vol=Math.max(1e-4,.5*V.len(V.cross(V.sub(B,A),V.sub(C,A)))*2*half);const m=WOOD.rho*vol;
  const b=makeBody([{p:cen,m,I:cylI(m,.04,2*half,V.norm(Q.rot(tr.q,w.l)))}],P,[{a:V.add(cen,V.mul(Q.rot(tr.q,w.l),-half*.8)),b:V.add(cen,V.mul(Q.rot(tr.q,w.l),half*.8)),r:.025}],[0,0,0,1],[0,0,0],{wedge:true});
  b.gpu=RD.upload(mb);b.v=V.add(V.mul(Q.rot(tr.q,w.face),.6),[0,.3,0]);PHYS.bodies.push(b);SFX.crunch();}

/* ---------- the slot the chain eats: a surface point inside the kerf is pushed in to the cut front ---------- */
function kerfGroove(p,c,r){const d=V.dot(c.n,V.sub(p,c.e));if(Math.abs(d)>SAWC.kerf)return null;const along=V.dot(V.sub(p,c.e),c.f);if(along>c.s)return null;
  const depth=Math.min(c.s-along+.004,r*.98);const rl=Math.hypot(p[0],p[2])||1;const k=Math.max(.02,(rl-depth)/rl);return [p[0]*k,p[1],p[2]*k];}
/* ---------- standing tree mesh with real kerfs and open faces ---------- */
function rebuildStanding(){const tr=G.tree;if(tr.mesh)RD.free(tr.mesh);tr.mesh=RD.upload(buildStandingMesh(tr.T,tr.cuts,Object.values(tr.freed||{})));}
function buildStandingMesh(T,cuts,wedges){const mb=new MeshB(),seg=36;
  const live=cuts.filter(c=>c.s>.002);
  // ring heights: coarse along the stem, fine through the cut band
  const ys=new Set();for(let y=-.4;y<T.H;y+=.3)ys.add(+y.toFixed(3));ys.add(T.H);
  if(live.length){let lo=1e9,hi=-1e9;for(const c of live){const R=T.rAt(clamp(c.e[1],0,T.H));const ext=Math.abs(c.n[1])>.05?R*Math.hypot(c.n[0],c.n[2])/Math.abs(c.n[1]):.3;lo=Math.min(lo,c.e[1]-Math.min(ext,.5)-.02);hi=Math.max(hi,c.e[1]+Math.min(ext,.5)+.02);}
    for(let y=Math.max(-.39,lo);y<=hi;y+=.005)ys.add(+y.toFixed(4));}
  const Y=[...ys].filter(y=>y>=-.4&&y<=T.H).sort((a,b)=>a-b);
  const rows=[];for(const y of Y){const r=T.rAt(Math.max(y,0)),row=[];const band=live.length&&y>-.39&&y<T.H-.01;
    for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;let p=[Math.cos(a)*r,y,Math.sin(a)*r],col=null;
      if(band){for(const w of wedges){if(inWedge(w,p)){const d1=V.dot(w.c1.n,V.sub(p,w.c1.e)),d2=V.dot(w.c2.n,V.sub(p,w.c2.e));const c=Math.abs(d1)<Math.abs(d2)?w.c1:w.c2,d=c===w.c1?d1:d2;p=V.sub(p,V.mul(c.n,d));col=SAP;break;}}
        if(!col)for(const c of live){const g=kerfGroove(p,c,r);if(g){p=g;col=KERF;break;}}}
      row.push(mb.v(p,V.norm([Math.cos(a),.1,Math.sin(a)]),col||barkCol(T,y,a)));}rows.push(row);}
  for(let j=0;j<rows.length-1;j++)for(let s=0;s<seg;s++)mb.quad(rows[j][s],rows[j][s+1],rows[j+1][s+1],rows[j+1][s]);
  mb.sphere(0,T.H,0,T.rAt(T.H),.04,T.rAt(T.H),BARK,6,3);
  appendLimbs(mb,T,T.limbs.map(l=>l.id));
  return mb;}
function appendLimbs(mb,T,ids){const tmp=buildPieceMesh(T,{kind:'limbsOnly',limbs:ids},null);const off=mb.p.length/3;
  for(let i=0;i<tmp.p.length;i++){mb.p.push(tmp.p[i]);mb.n.push(tmp.n[i]);mb.c.push(tmp.c[i]);}for(const k of tmp.i)mb.i.push(k+off);}

/* ---------- stump and butt: cut faces follow the real cut planes ---------- */
function heightField(T,cuts,R,pick){const out=(x,z)=>{let y=null;for(const c of cuts){const h=cutSevers(c,x,z);if(h!=null)y=y==null?h:pick(y,h);}return y;};return out;}
function buildStumpMesh2(T,cuts,R,y0,barberDir){const mb=new MeshB(),seg=36;const live=cuts.filter(c=>c.s>.002);const lowAt=heightField(T,live,R,Math.min);
  const torn=y0+.03;const top=(x,z)=>{const h=lowAt(x,z);return h==null?torn+(Math.sin(x*91)*Math.cos(z*77))*.015:clamp(h,-.2,y0+.6);};
  let tMax=-1;for(let i=0;i<=12;i++)for(let j=0;j<=12;j++){const x=(i/12*2-1)*R,z=(j/12*2-1)*R;if(x*x+z*z<=R*R)tMax=Math.max(tMax,top(x,z));}
  const Y=[-.35,0];for(let y=.05;y<tMax+.03;y+=.015)Y.push(y);
  const rows=[];for(const y of Y){const r=T.rAt(Math.max(y,0)),row=[];for(let s2=0;s2<=seg;s2++){const a=s2/seg*Math.PI*2;const x=Math.cos(a)*r,z=Math.sin(a)*r;
      row.push(mb.v([x,Math.min(y,top(x,z)),z],[Math.cos(a),0,Math.sin(a)],barkCol(T,y,a)));}rows.push(row);}
  for(let j=0;j<rows.length-1;j++)for(let s2=0;s2<seg;s2++)mb.quad(rows[j][s2],rows[j][s2+1],rows[j+1][s2+1],rows[j+1][s2]);
  capField(mb,T,R,top,1,lowAt);
  if(barberDir){const r=T.rAt(y0);mb.push(M.T(-barberDir[0]*r*.55,y0,-barberDir[2]*r*.55));mb.tf(M.Ry(Math.atan2(barberDir[0],barberDir[2])));
    const w=r*1.3,hh=1.5;const out=[[-w/2,0],[w/2,0],[w*.42,hh*.45],[w*.2,hh*.62],[w*.26,hh*.78],[w*.02,hh],[-w*.12,hh*.82],[-w*.3,hh*.66],[-w*.42,hh*.38]];
    mb.prism(out,-r*.22,r*.22,SAP,shade(SAP,.85));mb.prism(out.map(([x,y])=>[x*1.02,y*.97]),-r*.26,-r*.2,BARK,BARK);
    for(let k=0;k<7;k++){const x=-w/2+k*w/6;mb.tube([x,hh*(.3+.08*(k%3)),r*.22],[x+.01,hh*(.52+.1*(k%2)),r*.25],.008,.002,SAP,4);}mb.pop();}
  return mb;}
// polar grid cap whose height follows a field; up = +1 for a top face, −1 for a bottom face
function capField(mb,T,R,hy,up,cutAt){const NR=7,NS=36;const grid=[];
  for(let i=0;i<=NR;i++){const rr=R*i/NR*.995,row=[];for(let s=0;s<=NS;s++){const a=s/NS*Math.PI*2,x=Math.cos(a)*rr,z=Math.sin(a)*rr;const cut=cutAt(x,z)!=null;
      const ring=rr/R;const col=cut?(ring>.86?SAP:ring>.5?shade(HEART,1.06):HEART):mixc(SAP,BARK_D,.35);row.push(mb.v([x,hy(x,z),z],[0,up,0],col));}grid.push(row);}
  for(let i=0;i<NR;i++)for(let s=0;s<NS;s++){if(up>0)mb.quad(grid[i][s],grid[i+1][s],grid[i+1][s+1],grid[i][s+1]);else mb.quad(grid[i][s],grid[i][s+1],grid[i+1][s+1],grid[i+1][s]);}}
// bottom of the felled stem: the face shaped by the highest cut in each column
function buttCap(mb,T,P,hiAt){const live=P.butt.cuts.filter(c=>c.s>.002);const raw=heightField(T,live,T.rAt(P.y0),Math.max);
  const hy=(x,z)=>hiAt(x,z)+(raw(x,z)==null?-(Math.sin(x*83)*Math.cos(z*71))*.012:0);
  capField(mb,T,T.rAt(P.y0-.15),hy,-1,raw);}

/* ---------- carrying and feeding brush the right way round ---------- */
function brushAxis(b){const P=b.piece;if(P&&P.kind==='limb'){const L=G.tree.T.limbs[P.limb];return {ax:L.dir,butt:limbPt(L,P.t0||0)};}return {ax:[0,1,0],butt:[0,P?P.y0:0,0]};}
function orientAxis(q,axLocal,target,k){const cur=Q.rot(q,axLocal);const t=Q.mul(Q.between(V.norm(cur),V.norm(target)),q);return Q.norm(Q.slerp(q,t,k));}
