/* =====================================================================
   Arbor Simulator · game.js
   Level 1: "Earl's dead ash". Intro drive, the client, felling, limbing,
   bucking, chipping, stacking rounds, payday.
   ===================================================================== */
'use strict';

const G={phase:'title',t:0,keys:{},mouse:{l:false},money:0,seed:0,lock:false};
const $=id=>document.getElementById(id);
let RD=null;   // renderer

/* ---------------- persistence ---------------- */
function loadCareer(){try{return JSON.parse(localStorage.getItem('arbor.v1'))||{money:0,jobs:0};}catch(e){return {money:0,jobs:0};}}
function saveCareer(c){try{localStorage.setItem('arbor.v1',JSON.stringify(c));}catch(e){}}

/* ================= setup a new property ================= */
function newLevel(seed){
  // free old GPU meshes
  if(G.meshes)for(const k in G.meshes){const m=G.meshes[k];if(m&&m.vao)RD.free(m);}
  for(const b of PHYS.bodies)if(b.gpu)RD.free(b.gpu);PHYS.bodies.length=0;
  G.seed=seed;const W=makeWorld(seed);G.W=W;const R=RNG(seed+99);
  const mk=mb=>RD.upload(mb);
  G.meshes={terrain:mk(buildTerrain(W)),roads:mk(buildRoads(W)),house:mk(buildHouse(W)),woods:mk(buildWoods(W)),wheel:mk(buildWheel()),chipper:mk(buildChipper()),
    saw:mk(buildChainsaw()),gloveR:mk(buildGlove(1)),gloveL:mk(buildGlove(-1)),fistR:mk(buildFist(1)),fistL:mk(buildFist(-1)),arm:mk(buildArm()),can:mk(buildCan()),handCan:mk(buildRightHandCan()),forearm:mk(buildForearm()),shadow:mk(new MeshB().disk(0,0,0,1,[0,0,0],20))};
  const tk=buildTruck(R);G.meshes.truck=mk(tk.mesh);G.meshes.door=mk(buildTruckDoor(tk.c1,tk.c2));
  const om=buildOldMan();for(const k in om)G.meshes['om_'+k]=mk(om[k]);
  // truck path for the intro: along the road, then up the gravel drive
  const s=W.s;const ctrl=[[s*70,W.roadZ-1.8],[s*40,W.roadZ-1.8],[s*22,W.roadZ-1.6],...W.drive.slice(0,5)];
  G.path=spline(ctrl,10);G.pathLen=[0];for(let i=1;i<G.path.length;i++)G.pathLen.push(G.pathLen[i-1]+Math.hypot(G.path[i][0]-G.path[i-1][0],G.path[i][1]-G.path[i-1][1]));
  G.truck={pos:[0,0,0],yaw:0,pitch:0,roll:0,wheel:0,door:0,canOnSeat:false};
  G.chip={pos:[0,0,0],yaw:0,running:false,engine:null,feed:null,chips:0,mode:'truck',queue:[]};
  placeTruckAt(G.pathLen[G.pathLen.length-1]);settleTrailer(true);
  // the problem tree
  const tdef=W.tree;const T=makeTreeDef(tdef);const ld=[Math.cos(tdef.leanDir),0,Math.sin(tdef.leanDir)];
  G.tree={T,x:tdef.x,z:tdef.z,y0:W.H(tdef.x,tdef.z),q:Q.axis(V.cross([0,1,0],ld),tdef.lean),leanDir:ld,cuts:[],freed:{},state:'stand'};
  rebuildStanding();
  // old man
  G.om={x:W.oldMan.x,z:W.oldMan.z,yaw:0,state:'wave',t:0,talked:false,walkTo:null,bubble:null,bubbleT:0,lastBark:0};
  // player
  G.pl={pos:[0,0,0],yaw:0,pitch:0,vy:0,ground:true,tool:'hands',carryList:[],stepT:0,bob:0};
  Object.defineProperty(G.pl,'carry',{get(){return this.carryList[0]||null;},set(v){this.carryList=v?[v]:[];}});resetDust();
  G.saw={on:false,rpm:0,pull:0,pulls:0,engine:null,cutting:false,roll:Math.PI/2,eng:0,cut:null};
  G.cut=null;G.parts=[];G.wedge=null;G.objs={talk:false,felled:false,limbed:false,stacked:false,paid:false};G.grade=null;G.startT=performance.now();G.flags={};
  G.dlg=null;G.toastT=0;
  updateObjectives();
}
function buildTruckDoor(c1,c2){const mb=new MeshB();const vinyl=hex('#b89a6a');
  // left door, hinge at origin (front edge), extends toward −Z (rear)
  mb.box(-.03,.98,-.73,.06,.66,1.46,c1);mb.box(-.05,.98,-.73,.03,.3,1.4,c2);mb.box(-.03,1.33,-.73,.05,.05,1.45,c1);
  mb.box(.03,.98,-.73,.03,.5,1.3,shade(vinyl,.8));mb.box(-.03,1.63,-1.38,.05,.62,.06,c2);mb.box(-.03,1.92,-.75,.05,.05,1.3,c2);
  mb.box(-.07,1.12,-1.2,.03,.03,.14,hex('#c9ccd0'));return mb;}

/* ---------------- truck + trailer kinematics ---------------- */
function pathAt(d){const L=G.pathLen;d=clamp(d,0,L[L.length-1]);let i=1;while(i<L.length-1&&L[i]<d)i++;const t=(d-L[i-1])/((L[i]-L[i-1])||1);const a=G.path[i-1],b=G.path[i];return [[lerp(a[0],b[0],t),lerp(a[1],b[1],t)],Math.atan2(b[0]-a[0],b[1]-a[1])];}
function placeTruckAt(d){const W=G.W,tk=G.truck;const [p,yaw]=pathAt(d);const [p2]=pathAt(d+1.6),[p0]=pathAt(d-1.6);
  tk.yaw=Math.atan2(p2[0]-p0[0],p2[1]-p0[1])||yaw;tk.pos=[p[0],W.H(p[0],p[1]),p[1]];
  const f=[Math.sin(tk.yaw),0,Math.cos(tk.yaw)],r=[Math.cos(tk.yaw),0,-Math.sin(tk.yaw)];
  const hF=W.H(p[0]+f[0]*1.6,p[1]+f[2]*1.6),hB=W.H(p[0]-f[0]*1.6,p[1]-f[2]*1.6),hL=W.H(p[0]-r[0]*.8,p[1]-r[2]*.8),hR=W.H(p[0]+r[0]*.8,p[1]+r[2]*.8);
  tk.pitch=Math.atan2(hF-hB,3.2);tk.roll=Math.atan2(hL-hR,1.6);tk.pos[1]=(hF+hB)/2;}
function truckMatrix(){const tk=G.truck;return M.mul(M.mul(M.T(tk.pos[0],tk.pos[1],tk.pos[2]),M.Ry(tk.yaw)),M.mul(M.Rx(-tk.pitch),M.Rz(tk.roll)));}
function hitchWorld(){return M.apply(truckMatrix(),TRUCK.hitch);}
function settleTrailer(reset){const c=G.chip,h=chipHitchPoint();const L=-CHIP.axle;
  if(reset){const tk=G.truck;c.yaw=tk.yaw;}
  // axle trails behind the hitch at fixed distance
  // the axle stays where it was and the tongue swings to point at the new hitch position
  let ax=(!reset&&c.axle)?c.axle:[h[0]-Math.sin(c.yaw)*L,0,h[2]-Math.cos(c.yaw)*L];const d=[h[0]-ax[0],h[2]-ax[2]];c.yaw=Math.atan2(d[0],d[1]);
  ax=[h[0]-Math.sin(c.yaw)*L,0,h[2]-Math.cos(c.yaw)*L];c.pos=[h[0],h[1]-.5,h[2]];c.axle=[ax[0],G.W.H(ax[0],ax[2]),ax[2]];
  c.pitch=Math.asin(clamp((c.axle[1]+TRUCK.wheelR-c.pos[1]+.1)/2.3,-.5,.5));}
function chipMatrix(){const c=G.chip;return M.mul(M.mul(M.T(c.pos[0],c.pos[1],c.pos[2]),M.Ry(c.yaw)),M.Rx(c.pitch||0));}
function hopperWorld(){return M.apply(chipMatrix(),[0,1.0,-3.6]);}
function chuteWorld(){return M.apply(chipMatrix(),[0,2.45,-.9]);}

/* ================= bodies (felled stem, limbs, rounds) ================= */
function spawnPiece(P,q,origin,v,w){const T=G.tree.T;const g=pieceGeom(T,P);const b=makeBody(g.S,g.pts,g.caps,q,origin,{piece:P});
  b.mb=buildPieceMesh(T,P,null);b.gpu=RD.upload(b.mb);if(v)b.v=v.slice();if(w)b.w=w.slice();PHYS.bodies.push(b);classify(b);return b;}
function classify(b){const P=b.piece,T=G.tree.T;if(!P){b.brush=false;b.round=false;return;}
  if(P.kind==='limb'){b.brush=true;b.round=false;return;}
  const rMax=T.rAt(P.y0);b.brush=rMax<WOOD.brushR;b.round=!b.brush&&P.limbs.length===0;}
function frameOrigin(b){return V.sub(b.pos,Q.rot(b.q,b.com));}
function removeBody(b){b.mode='gone';const i=PHYS.bodies.indexOf(b);if(i>=0)PHYS.bodies.splice(i,1);if(b.gpu)RD.free(b.gpu);}
function velAtWorld(b,p){const r=V.sub(p,b.pos);return V.add(b.v,V.cross(b.w,r));}

function buckBody(b,y){const P=b.piece;if(y-P.y0<.04||P.y1-y<.04)return false;
  const o=frameOrigin(b),q=b.q;const kerfY=k=>k.e[1]+(k.n[0]*k.e[0]+k.n[2]*k.e[2])/(Math.abs(k.n[1])>1e-3?k.n[1]:1e-3);const T0=G.tree.T;
  // half-done kerfs right next to this cut (a second pass from the other side, a re-angled start) are gone with the sawn-through wood
  const left=(P.kerfs||[]).filter(k=>{if(k.s>=k.exit)return false;const ny=Math.abs(k.n[1]);if(ny<.3)return false;const ext=Math.min(.4,T0.rAt(clamp(y,0,T0.H))*Math.hypot(k.n[0],k.n[2])/ny);return Math.abs(kerfY(k)-y)>ext+.06;});
  const A={kerfs:left.filter(k=>kerfY(k)<y),kind:'trunk',y0:P.y0,y1:y-SAWC.kerf,limbs:P.limbs.filter(id=>G.tree.T.limbs[id].y<y),stubs:(P.stubs||[]).slice(),cutBottom:P.cutBottom,butt:P.butt,lt:P.lt};
  const Bp={kerfs:left.filter(k=>kerfY(k)>=y),kind:'trunk',y0:y+SAWC.kerf,y1:P.y1,limbs:P.limbs.filter(id=>G.tree.T.limbs[id].y>=y),stubs:(P.stubs||[]).slice(),cutBottom:true,lt:P.lt};
  removeBody(b);const nb=[];for(const Pn of [A,Bp]){const g=pieceGeom(G.tree.T,Pn);let c=[0,0,0],m=0;for(const s of g.S){c=V.add(c,V.mul(s.p,s.m));m+=s.m;}c=V.mul(c,1/m);
    const wc=V.add(o,Q.rot(q,c));nb.push(spawnPiece(Pn,q,o,velAtWorld(b,wc),b.w));}if(G.tree.body===b)G.tree.body=nb[0];
  nb.forEach(b2=>{wake(b2);for(const k of b2.piece.kerfs||[])k.b=b2;});SFX.crunch();return true;}
// cut a limb part way out: the stretch beyond t falls, a stub stays on the stem
function cutLimbAt(b,id,t){const P=b.piece;const o=frameOrigin(b),q=b.q;const [ta,tb]=limbSpan(P,id);
  const rest=Object.assign({},P,{lt:Object.assign({},P.lt||{},{[id]:t})});removeBody(b);const tb2=spawnPiece(rest,q,o,b.v,b.w);if(G.tree.body===b)G.tree.body=tb2;
  const lb=spawnPiece({kind:'limb',limb:id,t0:t,t1:tb},q,o,b.v,b.w);wake(tb2);wake(lb);SFX.crunch();return lb;}
function splitLimbPiece(b,t){const P=b.piece;const o=frameOrigin(b),q=b.q;removeBody(b);
  const A=spawnPiece({kind:'limb',limb:P.limb,t0:P.t0||0,t1:t},q,o,b.v,b.w),B=spawnPiece({kind:'limb',limb:P.limb,t0:t,t1:P.t1==null?1:P.t1},q,o,b.v,b.w);wake(A);wake(B);SFX.crunch();}
function limbBody(b,id){const P=b.piece;const o=frameOrigin(b),q=b.q;
  const rest=Object.assign({},P,{limbs:P.limbs.filter(x=>x!==id),stubs:[...(P.stubs||[]),id]});
  removeBody(b);const tb=spawnPiece(rest,q,o,b.v,b.w);if(G.tree.body===b)G.tree.body=tb;const lb=spawnPiece({kind:'limb',limb:id,t0:0,t1:limbSpan(P,id)[1]},q,o,b.v,b.w);
  // nudge the limb away from the stem so it drops clear
  const L=G.tree.T.limbs[id];const away=V.norm(Q.rot(q,[L.dir[0],0,L.dir[2]]));lb.v=V.add(lb.v,V.mul(away,.4));wake(tb);wake(lb);SFX.crunch();return lb;}

/* ================= felling ================= */
function treeD(h){return 2*G.tree.T.rAt(h);}
function hingeStep(dt){const tr=G.tree,hg=tr.hinge,b=hg.body;if(!hg||b.mode!=='hinge')return;
  const R=M3.fromQ(b.q),Iw=M3.mul(M3.mul(R,b.Ib),M3.T(R));const a=hg.axis;
  const rc=V.sub(b.pos,hg.Pc),tau=V.dot(V.cross(rc,[0,-PHYS.g*b.m,0]),a);
  const rp=V.sub(b.pos,hg.P),perp=V.sub(rp,V.mul(a,V.dot(rp,a)));const Ia=V.dot(a,M3.vec(Iw,a))+b.m*V.dot(perp,perp);
  hg.td+=(tau/Ia)*dt-hg.td*.15*dt;hg.th+=hg.td*dt;hg.t+=dt;
  const rq=Q.axis(a,hg.th);b.q=Q.norm(Q.mul(rq,hg.q0));b.pos=V.add(hg.P,Q.rot(rq,V.sub(hg.pos0,hg.P)));
  // release from the hinge once it is well over or something touches the ground
  let touch=false;if(hg.th>.5){const Rb=M3.fromQ(b.q);for(const lp of b.pts){const p=V.add(b.pos,M3.vec(Rb,lp));if(p[1]<G.W.H(p[0],p[2])){touch=true;break;}}}
  if(hg.th>1.25||touch){b.mode='dyn';b.w=V.mul(a,hg.td);b.v=V.cross(b.w,V.sub(b.pos,hg.P));tr.state='down';tr.downT=performance.now();SFX.crack();}}

/* ================= particles ================= */
function emit(p,v,n,col,spread,life,size,dust){for(let i=0;i<n;i++){if(G.parts.length>700)G.parts.shift();
  G.parts.push({p:p.slice(),v:[v[0]+(Math.random()-.5)*spread,v[1]+(Math.random()-.2)*spread,v[2]+(Math.random()-.5)*spread],life:dust?8:life*(0.6+Math.random()*.6),age:0,col:shade(col,.8+Math.random()*.4),s:size*(0.6+Math.random()*.8),dust});}}
function stepParts(dt){const H=G.W.H;for(const q of G.parts){q.age+=dt;q.v[1]-=6*dt;q.v=V.mul(q.v,1-1.2*dt);q.p=V.add(q.p,V.mul(q.v,dt));const g=H(q.p[0],q.p[2])+.01;if(q.p[1]<g){q.p[1]=g;q.v=[0,0,0];if(q.dust){addDust(q.p[0],q.p[2],q.s*q.s*3.5,q.dust==='chip');q.age=q.life;}}}
  G.parts=G.parts.filter(q=>q.age<q.life);}
function partMesh(){const mb=new MeshB();for(const q of G.parts){const s=q.s*(1-q.age/q.life*.5);mb.box(q.p[0],q.p[1],q.p[2],s,s*.6,s,q.col);}return mb;}

/* ================= old man ================= */
const OM_NAME='Earl';
const OM_IDLE=["Did I ever tell ya about the squirrel that robbed me? Took a whole bag of peanuts. Looked me dead in the eye.","Them little green beetles came all the way here just to ruin MY tree. I take that personal.","My cousin Del didn't watch his hinge. Now he sells insurance.","Don't mind the chickens. Wait, I don't have chickens. Whose chickens are those?","That tree's been creakin' at me every night for two years. Plottin', I tell ya.","You want a coffee? I don't have coffee. Just askin' if you WANT one.","Back in my day we cut trees with a butter knife and a positive attitude."];
function omBark(text,ms){const o=G.om;o.bubble=text;o.bubbleT=performance.now()+(ms||3000);}
function updateOldMan(dt){const o=G.om,P=G.pl.pos;o.t+=dt;
  if(o.walkTo){const dx=o.walkTo[0]-o.x,dz=o.walkTo[1]-o.z,d=Math.hypot(dx,dz);if(d<.15){o.walkTo=null;o.state=o.after||'idle';}else{const sp=(o.dodgeT&&performance.now()-o.dodgeT<3000?1.8:1.1)*dt;o.x+=dx/d*Math.min(sp,d);o.z+=dz/d*Math.min(sp,d);o.yaw=Math.atan2(dx,dz);o.state='walk';}}
  else{const want=Math.atan2(P[0]-o.x,P[2]-o.z);let dy=want-o.yaw;while(dy>Math.PI)dy-=Math.PI*2;while(dy<-Math.PI)dy+=Math.PI*2;if(G.phase==='play'||o.state==='wave')o.yaw+=dy*Math.min(1,dt*3);}
  // safety: once the saw is running near the tree he heads for the porch
  if(G.phase==='play'&&G.objs.talk&&!o.toPorch&&G.saw.on&&Math.hypot(P[0]-G.tree.x,P[2]-G.tree.z)<G.tree.T.H){o.toPorch=true;o.walkTo=G.W.porch.slice();o.after='idle';omBark("I'll be on the porch! If that thing lands on my house I'm keepin' your truck!",4000);}
  // idle chatter while you work
  if(G.phase==='play'&&G.objs.felled&&!G.objs.paid&&performance.now()-o.lastBark>38000&&!G.dlg){o.lastBark=performance.now();omBark(OM_IDLE[Math.floor(Math.random()*OM_IDLE.length)],5000);}}
function omMatrices(){const o=G.om,y=G.W.H(o.x,o.z),t=o.t;const root=M.mul(M.T(o.x,y,o.z),M.Ry(o.yaw+Math.PI));
  const walk=o.state==='walk',sw=walk?Math.sin(t*6)*.5:0;const hip=M.mul(root,M.T(0,.92+(walk?Math.abs(Math.cos(t*6))*.03:Math.sin(t*1.3)*.005),0));
  const torso=M.mul(hip,M.Rx(walk?.08:.12+Math.sin(t*1.1)*.02));const neck=M.mul(torso,M.T(0,.58,0));
  const talking=G.dlg&&G.dlg.who===OM_NAME&&!G.dlg.done;const head=M.mul(neck,M.mul(M.Rx(talking?Math.sin(t*9)*.08:-.05),M.Ry(Math.sin(t*.7)*.15)));
  const arm=(side)=>{const sh=M.mul(torso,M.T(side*.25,.5,0));let up,fore;
    if(o.state==='wave'&&side>0){up=M.mul(M.Rz(side*2.5),M.Rx(-.2));fore=M.Rz(side*(.5+Math.sin(t*8)*.45));}
    else if(talking&&side<0){up=M.mul(M.Rz(side*-.35),M.Rx(-.6-Math.sin(t*3)*.3));fore=M.Rx(-.9);}
    else{up=M.mul(M.Rz(side*.12),M.Rx(walk?-sw*side*.8:Math.sin(t*1.2+side)*.04));fore=M.Rx(-.25);}
    const U=M.mul(sh,up),F=M.mul(U,M.mul(M.T(0,-.3,0),fore));return [U,F];};
  const [uR,fR]=arm(1),[uL,fL]=arm(-1);
  const legL=M.mul(hip,M.mul(M.T(-.1,0,0),M.Rx(sw))),legR=M.mul(hip,M.mul(M.T(.1,0,0),M.Rx(-sw)));
  const cane=M.mul(fL,M.T(0,-.3,0));
  return {torso,head:neck,headR:head,uR,fR,uL,fL,legL,legR,cane};}

/* ================= dialogue ================= */
function startDialog(lines,onDone){G.dlg={lines,i:0,shown:0,done:false,onDone,who:lines[0].who,lastBlip:0};try{document.exitPointerLock();}catch(e){}$('dialog').hidden=false;renderDialog();}
function renderDialog(){const d=G.dlg;if(!d)return;const L=d.lines[d.i];d.who=L.who;$('dlgName').textContent=L.who;$('dlgText').textContent=L.text.slice(0,Math.floor(d.shown));
  $('dlgHint').textContent=d.shown>=L.text.length?(d.i<d.lines.length-1?'Click or E to continue':'Click or E to close'):'';}
function advanceDialog(){const d=G.dlg;if(!d)return;const L=d.lines[d.i];if(d.shown<L.text.length){d.shown=L.text.length;renderDialog();return;}
  if(d.i<d.lines.length-1){d.i++;d.shown=0;renderDialog();return;}
  $('dialog').hidden=true;G.dlg=null;if(d.onDone)d.onDone();}
function stepDialog(dt){const d=G.dlg;if(!d)return;const L=d.lines[d.i];if(d.shown<L.text.length){d.shown=Math.min(L.text.length,d.shown+dt*48);
  if(L.who===OM_NAME&&performance.now()-d.lastBlip>70&&/[a-z]/i.test(L.text[Math.floor(d.shown)]||'')){d.lastBlip=performance.now();SFX.blip(150+Math.random()*70);}renderDialog();}}
function talkToEarl(){const o=G.om;
  if(!G.objs.talk){startDialog([
    {who:OM_NAME,text:"Well it's about dang time! You the tree fella? You look like a tree fella."},
    {who:OM_NAME,text:"That ash out back's deader'n disco. Them little green beetles got it. Emerald ash borers, the TV called 'em."},
    {who:OM_NAME,text:"It creaks at me every night. Every. Night. Like it's plottin' somethin'."},
    {who:OM_NAME,text:"Here's the deal: drop it, chip the branches, and cut the trunk into rounds I can lift. Stack 'em on the pallet by my shed."},
    {who:OM_NAME,text:"Four hundred bucks, cash. From my mattress. Don't ask about the mattress."},
    {who:OM_NAME,text:"Go on, git! And don't drop it on my house."}],()=>{G.objs.talk=true;o.state='idle';updateObjectives();});return;}
  if(G.objs.felled&&G.objs.limbed&&G.objs.stacked&&!G.objs.paid){payday();return;}
  startDialog([{who:OM_NAME,text:OM_IDLE[Math.floor(Math.random()*OM_IDLE.length)]}]);}
function payday(){const g=G.tree.grade||{};const lines=[];let total=400;const rows=[['Job: drop, limb, chip and stack',400]];
  const clean=g.open&&!g.barber&&g.notchPct>=.18&&g.notchPct<=.45&&g.notchAngle>=40&&g.hingePct>=.05&&g.hingePct<=.18&&g.dirErr<15;
  if(clean){rows.push(['Textbook felling (notch, hinge, aim)',50]);total+=50;}
  if(g.barber){rows.push(['Barber chair (Earl is shaken)',-100]);total-=100;}
  const mins=(performance.now()-G.startT)/60000;if(mins<15){rows.push(['Quick work (under 15 min)',25]);total+=25;}
  lines.push({who:OM_NAME,text:"Well I'll be. Look at that. Neat as a pin!"},{who:OM_NAME,text:"Here's your money. Mostly twenties. One's Canadian, don't ask."},{who:OM_NAME,text:"I got a buddy with a whole yard of sick maples. I'll put in a good word. Maybe."});
  startDialog(lines,()=>{G.objs.paid=true;updateObjectives();SFX.cash();const c=loadCareer();c.money+=total;c.jobs++;saveCareer(c);G.money=c.money;showSummary(rows,total,g,mins);});}

/* ================= HUD ================= */
function toast(msg,ms){const el=$('toast');el.textContent=msg;el.classList.add('on');G.toastT=performance.now()+(ms||3200);}
function shout(msg){const el=$('shout');el.textContent=msg;el.classList.remove('on');void el.offsetWidth;el.classList.add('on');}
function updateObjectives(){const o=G.objs;let brush=0;for(const b of PHYS.bodies){if(b.mode==='gone'||!b.piece)continue;if(b.brush)brush++;else if(b.piece.kind==='trunk')brush+=b.piece.limbs.length;}
  const rounds=PHYS.bodies.filter(b=>b.mode!=='gone'&&b.round);const inPile=rounds.filter(inPileZone).length;const heavy=rounds.filter(b=>b.m>WOOD.liftMax).length;
  if(o.felled){o.limbed=brush===0;o.stacked=o.limbed&&rounds.length>0&&heavy===0&&inPile===rounds.length;}
  const li=(done,txt)=>`<li class="${done?'done':''}">${txt}</li>`;
  $('objList').innerHTML=li(o.talk,'Talk to Earl')+li(o.felled,'Drop the dead ash')+li(o.limbed,`Limb it and chip the brush${o.felled&&!o.limbed?` · ${brush} left`:''}`)
    +li(o.stacked,`Buck the stem into liftable rounds and stack them on the pallet${o.felled&&rounds.length?` · ${inPile}/${rounds.length}${heavy?` · ${heavy} too heavy`:''}`:''}`)+li(o.paid,'Get paid');
  G.counts={brush,rounds:rounds.length,inPile,heavy};
  if(o.limbed&&o.stacked&&!o.paid&&!G.flags.callPay){G.flags.callPay=true;SFX.ding();omBark("Hey! Looks done to me! Come get your money!",6000);toast('Job done. Talk to Earl to get paid.');}}
function inPileZone(b){const p=G.W.pile;return Math.abs(b.pos[0]-p.x)<p.w/2+.6&&Math.abs(b.pos[2]-p.z)<p.d/2+.6;}
function showSummary(rows,total,g){const el=$('summary');el.hidden=false;
  $('sumRows').innerHTML=rows.map(([k,v])=>`<div class="row"><span>${k}</span><b class="${v<0?'neg':''}">${v<0?'−':'+'}$${Math.abs(v)}</b></div>`).join('')+`<div class="row total"><span>Total</span><b>$${total}</b></div>`;
  const notes=[];if(g&&g.notchPct!=null){if(g.open){notes.push(`Notch: ${(g.notchPct*100).toFixed(0)}% of the diameter deep, ${g.notchAngle.toFixed(0)}° open.`);notes.push(`Hinge: ${g.hingeIn.toFixed(1)} in, ${(g.hingePct*100).toFixed(0)}% of the diameter.`);notes.push(`Fell direction: ${g.dirErr.toFixed(0)}° off the notch.`);}
    else notes.push(g.barber?'The stem split up the back (barber chair).':'No notch was cut.');}
  $('sumNotes').innerHTML=notes.map(n=>`<li>${n}</li>`).join('');$('sumBank').textContent=`Bank: $${loadCareer().money}`;try{document.exitPointerLock();}catch(e){}}
/* ================= input ================= */
function onKey(e,down){const k=e.code;G.keys[k]=down;if(!down)return;
  if(G.phase==='intro'&&(k==='Space'||k==='Enter'||k==='Escape')){G.introSkip=true;return;}
  if(G.phase!=='play')return;
  if(G.dlg){if(k==='KeyE'||k==='Space'||k==='Enter')advanceDialog();return;}
  if(G.pl.inTruck){if(k==='KeyE')exitTruck();else if(k==='KeyV')G.drive.chase=!G.drive.chase;else if(k==='KeyH')$('help').hidden=!$('help').hidden;return;}
  if(k==='KeyE')interact();
  else if(k==='KeyQ'&&G.pl.carry)dropOne();
  else if(k==='Digit1')equip('hands');
  else if(k==='Digit2')equip('saw');
  else if(k==='Digit3')toggleMuffs();
  else if(k==='KeyF')kick();
  else if(k==='KeyR'&&G.pl.tool==='saw')pullStart();
  else if(k==='KeyH'){$('help').hidden=!$('help').hidden;}
  else if(k==='KeyC'||k==='ControlLeft'){G.pl.crouch=!G.pl.crouch;}
  else if(k==='Space'&&G.pl.ground){G.pl.vy=4.2;G.pl.ground=false;}}
function equip(t){const p=G.pl;if(t==='saw'&&G.saw.racked){toast('The saw is on the chipper rack.',1800);return;}if(p.carry)dropCarry();if(t===p.tool)return;p.tool=t;if(t!=='saw'&&G.saw.on){sawOff();}
  document.querySelectorAll('.slot[data-t]').forEach(s=>s.classList.toggle('on',s.dataset.t===t));if(t==='saw'&&!G.saw.on)toast('Press R to pull-start the saw.',2200);}
function pullStart(){const s=G.saw;if(s.on){sawOff();return;}if(s.pull>0)return;s.pull=.5;s.pulls++;SFX.pull();
  setTimeout(()=>{if(G.pl.tool!=='saw')return;if(s.pulls>=2&&Math.random()<.6||s.pulls>=4){s.on=true;s.pulls=0;s.engine=makeEngine('saw');toast('Saw running.',1800);}else{SFX.sputter();toast(s.pulls===1?'Choke is on. Pull again.':'Sputter… pull again.',1400);}},380);}
function sawOff(){const s=G.saw;s.on=false;if(s.engine){s.engine.stop();s.engine=null;}s.cutting=false;}

/* ================= interaction ================= */
function hopTruck(){const p=G.pl,tm=truckMatrix();if(p.carryList.length>1)dropCarry();
  if(p.onBed){const o=M.apply(tm,[0,0,-3.7]);p.pos=[o[0],G.W.H(o[0],o[2]),o[2]];p.onBed=false;}
  else{const o=M.apply(tm,[0,.775,-2.1]);p.pos=o;p.onBed=true;p.vy=0;}SFX.step();}
// a boot to whatever you're looking at: shoves it, and snaps a piece that is nearly cut through
function kick(){const p=G.pl;if(p.carry||p.inTruck)return;const eye=V.add(p.pos,[0,p.eyeY||1.62,0]),d=fwdOf(p.yaw,Math.min(p.pitch,-.15));
  const h=rayBodies(eye,d,1.9,b=>b.mode==='dyn'&&!!b.piece);G.kickT=performance.now();if(!h){SFX.step();return;}const b=h.b;wake(b);
  const k=(b.piece.kerfs||[]).filter(k=>k.s<k.exit&&k.s/k.exit>.72).sort((a,c)=>c.s/c.exit-a.s/a.exit)[0];
  if(k){k.b=b;k.s=k.exit+.01;SFX.crack();finishPieceCut(k);emit(h.p,[0,1.2,0],12,hex('#c4ae88'),2,1,.04,true);return;}
  const J=V.add(V.mul([d[0],0,d[2]],Math.min(220,b.m*3)),[0,Math.min(60,b.m*.8),0]);const r=V.sub(h.p,b.pos);b.v=V.add(b.v,V.mul(J,b.im));
  const R=M3.fromQ(b.q);const iIw=M3.mul(M3.mul(R,b.iIb),M3.T(R));b.w=V.add(b.w,M3.vec(iIw,V.cross(r,J)));SFX.thud(3);}
function rackAction(){const s=G.saw;if(s.racked){s.racked=false;G.pl.tool='hands';equip('saw');SFX.pick();return;}
  if(G.pl.tool!=='saw')return;sawOff();s.racked=true;G.pl.tool='hands';document.querySelectorAll('.slot[data-t]').forEach(x=>x.classList.toggle('on',x.dataset.t==='hands'));SFX.clank();}
function toggleMuffs(){G.muffs=!G.muffs;setMuffs(G.muffs);$('muffSlot').classList.toggle('on',G.muffs);SFX.pick();}
// branches squeeze into the infeed: everything inside the hood is pushed toward the throat, tips fold along the walls
function foldIntoHopper(b){const cm=chipMatrix(),inv=invRigid(cm),Mo=bodyMatrix(b),src=b.mb,out=new MeshB();out.i=src.i;out.c=src.c;out.n=src.n;const P=src.p,np=new Array(P.length);
  for(let k=0;k<P.length;k+=3){const w=M.apply(Mo,[P[k],P[k+1],P[k+2]]);const l=M.apply(inv,w);
    if(l[2]>-2.95){l[0]*=.1;l[1]=1.0+(l[1]-1.0)*.1;l[2]=Math.min(l[2],-2.85);}                                 // past the rollers: gone into the drum
    else if(l[2]>-4.3){const t=(l[2]+4.3)/1.35;const hw=lerp(.58,.34,t),hh=lerp(.44,.3,t);l[0]=clamp(l[0],-hw,hw);l[1]=clamp(l[1],1.0-hh,1.0+hh);}
    const q=M.apply(cm,l);np[k]=q[0];np[k+1]=q[1];np[k+2]=q[2];}
  out.p=np;return out;}
function aimInfo(){const p=G.pl,eye=V.add(p.pos,[0,G.pl.eyeY||1.62,0]),d=fwdOf(p.yaw,p.pitch);G.eye=eye;G.fwd=d;let best=null;
  // old man
  const o=G.om,om=[o.x,G.W.H(o.x,o.z)+1.2,o.z];{const to=V.sub(om,eye),dist=V.len(to);if(dist<3.2&&V.dot(V.norm(to),d)>.9)best={kind:'om',t:dist};}
  // the truck's driver door
  if(nearDriverDoor()){const dd=V.dist(M.apply(truckMatrix(),[-1.05,1.1,.2]),eye);if(!best||dd<best.t)best={kind:'truck',t:dd};}
  // the tailgate: hop up into the bed, or back down
  {const tg=M.apply(truckMatrix(),[0,1.1,-2.62]);const to=V.sub(tg,eye),dd=V.len(to);if(dd<2.3&&V.dot(V.norm(to),d)>.55&&(!best||dd<best.t))best={kind:'tailgate',t:dd};}
  // the saw rack on the chipper
  {const rp=M.apply(chipMatrix(),[-.7,.82,-2.2]);const to=V.sub(rp,eye),dd=V.len(to);if(dd<2.0&&V.dot(V.norm(to),d)>.85&&(G.pl.tool==='saw'||G.saw.racked)&&(!best||dd<best.t))best={kind:'rack',t:dd};}
  // the chipper's tongue coupler
  {const d=nearCoupler();if(d!=null&&(!best||d<best.t))best={kind:'hitch',t:d};}
  // chipper engine
  const ce=M.apply(chipMatrix(),[0,1.1,-1.6]);{const to=V.sub(ce,eye),dist=V.len(to);if(dist<2.4&&V.dot(V.norm(to),d)>.82&&(!best||dist<best.t))best={kind:'chipper',t:dist};}
  // standing tree
  const tr=G.tree;G.aimTree=null;if(tr.state==='stand'){const a=[tr.x,tr.y0,tr.z],b=[tr.x,tr.y0+tr.T.cb,tr.z];const h=rayCapsule(eye,d,2.3,a,b,tr.T.rAt(.8)+.05);
    if(h&&(!best||h.t<best.t)){best={kind:'tree',t:h.t,p:h.p,y:h.p[1]-tr.y0};G.aimTree=best;}}
  // pieces
  const rb=rayBodies(eye,d,2.4,b=>b!==G.pl.carry&&b.mode==='dyn');if(rb&&(!best||rb.t<best.t))best={kind:'body',t:rb.t,p:rb.p,b:rb.b,cap:rb.cap};
  return best;}
function interact(){const p=G.pl;const a=G.aim;
  if(G.chip.mode==='hand'){hitchAction();return;}
  if(p.carry){if(a&&a.kind==='body'&&p.tool==='hands'&&a.b.piece&&!(a.b.piece.kind==='trunk'&&a.b.piece.limbs.length)&&canAddCarry(a.b)){pickUp(a.b);return;}
    const hw=hopperWorld();if(V.dist(hw,G.eye)<3.4&&p.carry.brush&&G.chip.running){feedChipper();return;}dropCarry();return;}
  if(!a)return;
  if(a.kind==='hitch'){hitchAction();return;}
  if(a.kind==='tailgate'){hopTruck();return;}
  if(a.kind==='rack'){rackAction();return;}
  if(a.kind==='om'){talkToEarl();return;}
  if(a.kind==='truck'){enterTruck();return;}
  if(a.kind==='chipper'){toggleChipper();return;}
  if(a.kind==='body'&&p.tool==='hands'){const b=a.b;if(b.m>WOOD.liftMax){toast(`Too heavy to lift (${lb(b.m)}).`);return;}
    if(b.piece&&b.piece.kind==='trunk'&&b.piece.limbs.length){toast("Can't lift that.");return;}
    pickUp(b);return;}
  if(a.kind==='body'&&p.tool==='saw'&&!G.saw.on)toast('The saw is off.');}
function dropCarry(){const L=G.pl.carryList;if(!L.length)return;L.forEach((b,i)=>{releaseBody(b);b.v=V.add(b.v,[(i%2?.3:-.3),0,0]);});G.pl.carryList=[];SFX.drop();setTimeout(updateObjectives,1500);}
function toggleChipper(){const c=G.chip;if(c.running){c.running=false;if(c.engine){c.engine.stop();c.engine=null;}toast('Chipper off.');return;}
  SFX.pull();setTimeout(()=>{c.running=true;c.engine=makeEngine('chipper');toast('Chipper running.',1800);},500);}
function feedChipper(){const c=G.chip;if(!c.running){toast("The chipper isn't running.");return;}
  const L=G.pl.carryList.filter(b=>b.brush);G.pl.carryList=G.pl.carryList.filter(b=>!b.brush);for(const b of L){b.mode='feedwait';c.queue.push(b);}nextFeed();}
function nextFeed(){const c=G.chip;if(c.feed||!c.queue.length)return;const b=c.queue.shift();b.mode='feed';b.feedT=0;b.feedFrom=b.pos.slice();c.feed=b;}
function stepFeed(dt){const c=G.chip,b=c.feed;if(!b)return;b.feedT+=dt;const cm=chipMatrix();const throat=M.apply(cm,[0,1.0,-2.95]),mouth=M.apply(cm,[0,1.0,-4.25]);
  const ax=V.norm(V.sub(throat,mouth)),{ax:axL,butt}=brushAxis(b);const len=b.piece&&b.piece.kind==='limb'?G.tree.T.limbs[b.piece.limb].len*((b.piece.t1==null?1:b.piece.t1)-(b.piece.t0||0)):(b.piece?b.piece.y1-b.piece.y0:1);
  const tipL=V.add(butt,V.mul(axL,len));
  if(b.feedT<.7){// swing it level, butt toward the rollers, and set the butt in the mouth
    b.q=orientAxis(b.q,axL,V.mul(ax,-1),Math.min(1,dt*7));const want=V.sub(mouth,Q.rot(b.q,V.sub(butt,b.com)));b.pos=V.lerp(b.pos,want,Math.min(1,dt*7));}
  else{// the feed rollers grab it and drag it through
    b.q=orientAxis(b.q,axL,V.mul(ax,-1),Math.min(1,dt*10));b.pos=V.add(b.pos,V.mul(ax,1.5*dt));b.pos[1]+=(Math.random()-.5)*.01;
    const o=chuteWorld();emit(o,V.add(V.mul([Math.sin(c.yaw),0,Math.cos(c.yaw)],4),[0,1.5,0]),6,hex('#c9a46a'),1.6,1.4,.05,'chip');c.load=1;if(Math.random()<dt*6)SFX.crunch();
    const tipW=bodyWorld(b,tipL);if(V.dot(V.sub(tipW,throat),ax)>0||b.feedT>12){removeBody(b);c.feed=null;c.chips++;updateObjectives();nextFeed();}}}

/* ================= player movement ================= */
function obbPush(p,cx,cz,yaw,hx,hz,r){const c=Math.cos(yaw),s=Math.sin(yaw);const dx=p[0]-cx,dz=p[2]-cz;const lx=dx*c-dz*s,lz=dx*s+dz*c;
  const qx=clamp(lx,-hx,hx),qz=clamp(lz,-hz,hz);const ex=lx-qx,ez=lz-qz,d=Math.hypot(ex,ez);if(d>=r)return;let nx,nz,pen;
  if(d<1e-5){const px=hx-Math.abs(lx),pz=hz-Math.abs(lz);if(px<pz){nx=Math.sign(lx);nz=0;pen=px+r;}else{nx=0;nz=Math.sign(lz);pen=pz+r;}}else{nx=ex/d;nz=ez/d;pen=r-d;}
  const wx=nx*c+nz*s,wz=-nx*s+nz*c;p[0]+=wx*pen;p[2]+=wz*pen;}
function stepPlayer(dt){const p=G.pl,K=G.keys,W=G.W;p.eyeY=lerp(p.eyeY||1.62,p.crouch?.98:1.62,Math.min(1,dt*8));if(G.dlg)return;
  const f=[-Math.sin(p.yaw),0,-Math.cos(p.yaw)],r=[Math.cos(p.yaw),0,-Math.sin(p.yaw)];let mv=[0,0,0];
  if(K.KeyW)mv=V.add(mv,f);if(K.KeyS)mv=V.sub(mv,f);if(K.KeyD)mv=V.add(mv,r);if(K.KeyA)mv=V.sub(mv,r);
  const carryM=carryMass();const sp=(K.ShiftLeft&&!p.carry&&!p.crouch?5.6:p.crouch?1.4:3.3)*(1-carryM/WOOD.liftMax*.45)*(G.chip.mode==='hand'?.55:1);
  const moving=V.len(mv)>0;if(moving){mv=V.mul(V.norm(mv),sp*dt);p.pos[0]+=mv[0];p.pos[2]+=mv[2];p.stepT+=sp*dt;p.bob+=dt*sp*2.2;if(p.stepT>1.3&&p.ground){p.stepT=0;SFX.step();}}
  // collisions
  const rad=.34;for(const c of W.colliders){if(c.t==='circle'){const dx=p.pos[0]-c.x,dz=p.pos[2]-c.z,d=Math.hypot(dx,dz),m=c.r+rad;if(d<m&&d>1e-5){p.pos[0]=c.x+dx/d*m;p.pos[2]=c.z+dz/d*m;}}else obbPush(p.pos,c.x,c.z,0,c.hx,c.hz,rad);}
  const tk=G.truck,tmx=truckMatrix(),tinv=invRigid(tmx);
  // standing in the bed: the floor holds you up and the bed walls keep you in unless you jump over them
  {const l=M.apply(tinv,p.pos);const overBed=Math.abs(l[0])<.95&&l[2]>-2.6&&l[2]<-.78;
    if(p.onBed){if(!overBed||l[1]>1.3&&!overBed)p.onBed=false;else if(l[1]<1.25){l[0]=clamp(l[0],-.62,.62);l[2]=clamp(l[2],-2.3,-1.05);const w=M.apply(tmx,l);p.pos[0]=w[0];p.pos[2]=w[2];}}
    else if(overBed&&l[1]>.7)p.onBed=true;
    if(!p.onBed)obbPush(p.pos,tk.pos[0],tk.pos[2],tk.yaw,1.02,2.72,rad);}
  const cm=chipMatrix(),cc=M.apply(cm,[0,0,-2.4]);obbPush(p.pos,cc[0],cc[2],G.chip.yaw,.6,1.6,rad);
  const o=G.om;{const dx=p.pos[0]-o.x,dz=p.pos[2]-o.z,d=Math.hypot(dx,dz);if(d<.7&&d>1e-5){p.pos[0]=o.x+dx/d*.7;p.pos[2]=o.z+dz/d*.7;}}
  const tr=G.tree;{const rr=(tr.state==='stand'?tr.T.rAt(.5):tr.stumpH>0.6?tr.T.rAt(.5):0)+rad;if(tr.state==='stand'||tr.stumpH>.6){const dx=p.pos[0]-tr.x,dz=p.pos[2]-tr.z,d=Math.hypot(dx,dz);if(d<rr&&d>1e-5){p.pos[0]=tr.x+dx/d*rr;p.pos[2]=tr.z+dz/d*rr;}}}
  // logs: block the player, and get shoved when walked into
  for(const b of PHYS.bodies){if(b.mode!=='dyn'||b===p.carry)continue;if(V.dist(b.pos,p.pos)>b.rad+1.5)continue;const R=M3.fromQ(b.q);
    for(const k of b.caps){const a=V.add(b.pos,M3.vec(R,k.a)),c=V.add(b.pos,M3.vec(R,k.b));const feet=p.pos[1]+.25;
      const [cp]=closestOnSeg([p.pos[0],feet,p.pos[2]],a,c);if(cp[1]-k.r>p.pos[1]+1.0)continue;const dx=p.pos[0]-cp[0],dz=p.pos[2]-cp[2],d=Math.hypot(dx,dz),m=k.r+rad*.8;
      if(d<m&&d>1e-5){if(cp[1]+k.r<p.pos[1]+.45&&k.r<.35){continue;}  // small stuff: step over it
        p.pos[0]=cp[0]+dx/d*m;p.pos[2]=cp[2]+dz/d*m;if(moving&&b.m<900){wake(b);const push=V.mul([-dx/d,0,-dz/d],Math.min(1.8,260/b.m)*dt*6);b.v=V.add(b.v,push);}}}}
  // ground + gravity
  let gh=W.H(p.pos[0],p.pos[2]);if(p.onBed){const l=M.apply(tinv,p.pos);gh=M.apply(tmx,[l[0],.775,l[2]])[1];}p.vy-=9.81*dt;p.pos[1]+=p.vy*dt;if(p.pos[1]<=gh){p.pos[1]=gh;p.vy=0;p.ground=true;}
  // world bounds
  p.pos[0]=clamp(p.pos[0],-120,120);p.pos[2]=clamp(p.pos[2],-110,120);
  stepCarry(dt);}

/* ---------------- danger: the falling stem ---------------- */
function checkCrush(){const tr=G.tree,b=tr.body;if(!b||G.phase!=='play'||!(tr.state==='hinge'||(tr.state==='down'&&performance.now()-tr.downT<2500)))return;
  const p=G.pl.pos,R=M3.fromQ(b.q);for(const k of b.caps){const a=V.add(b.pos,M3.vec(R,k.a)),c=V.add(b.pos,M3.vec(R,k.b));
    const [cp,t]=closestOnSeg(V.add(p,[0,1,0]),a,c);const v=V.len(velAtWorld(b,cp));if(v<2.5)continue;
    if(Math.hypot(cp[0]-p[0],cp[2]-p[2])<k.r+.32&&cp[1]>p[1]-.2&&cp[1]<p[1]+1.9){die();return;}}}
function die(){G.phase='dead';sawOff();try{document.exitPointerLock();}catch(e){}SFX.thud(10);$('dead').hidden=false;}

/* ================= intro ================= */
const INTRO={drive:13,drink:4.6,door:2.6};
function stepIntro(dt){const I=G.intro;I.t+=dt;const total=INTRO.drive+INTRO.drink+INTRO.door;if(G.introSkip&&I.t<total-.2){I.t=total-.2;}
  const L=G.pathLen[G.pathLen.length-1];const td=clamp(I.t/INTRO.drive,0,1);const e=td<.15?(td/.15)*(td/.15)*.15/.15*.5*.3:0;
  // distance travelled: gentle ease in/out
  const d=L*(1-Math.pow(1-smooth(td),1.15));const prev=I.d||0;I.d=d;placeTruckAt(d);settleTrailer(false);G.truck.wheel+=(d-prev)/TRUCK.wheelR;
  const speed=(d-prev)/Math.max(dt,1e-3);
  if(I.eng)I.eng.set(clamp(speed/9,0,1)*(I.t<INTRO.drive?1:0)+.15,clamp(speed/12,0,.6),I.t<INTRO.drive+.6?.5:0);
  if(I.t>INTRO.drive+.6&&I.eng){I.eng.stop();I.eng=null;}
  // drink: lift, glug x3, crush, toss
  const dt0=I.t-INTRO.drive-.6;
  if(dt0>.9&&!I.g1){I.g1=1;SFX.glug(0);}if(dt0>1.5&&!I.g2){I.g2=1;SFX.glug(1);}if(dt0>2.1&&!I.g3){I.g3=1;SFX.glug(2);}
  if(dt0>2.9&&!I.cr){I.cr=1;SFX.canCrush();}if(dt0>3.8&&!I.tos){I.tos=1;setTimeout(()=>SFX.clank(),350);}
  if(dt0>4.4)G.truck.canOnSeat=true;
  const td2=I.t-INTRO.drive-INTRO.drink;if(td2>0&&!I.dr){I.dr=1;SFX.door();}
  G.truck.door=td2>0?smooth(clamp(td2/.7,0,1))*1.15:0;
  if(td2>2.2&&!I.sl){I.sl=1;}
  if(I.t>=total){endIntro();}
  // title card
  $('introCard').classList.toggle('on',I.t>1&&I.t<9);
  if(I.t>9.5&&!I.om){I.om=1;omBark("Over here! OVER HERE! I'm the one that called!",3500);}}
function introCamera(){const I=G.intro,tm=truckMatrix(),tk=G.truck;const eye=M.apply(tm,TRUCK.eye);
  const ty=tk.yaw+Math.PI;let yaw=ty+Math.sin(I.t*.4)*.04,pitch=-.06+tk.pitch;
  const dt0=I.t-INTRO.drive-.6;if(dt0>0&&dt0<4){const k=smooth(clamp(dt0/.8,0,1))*smooth(clamp((3.4-dt0)/.6,0,1));pitch+=k*.38;}
  // when the old man is in view, glance at him
  const o=G.om;const toOm=Math.atan2(-(o.x-eye[0]),-(o.z-eye[2]));if(I.t>INTRO.drive-4&&I.t<INTRO.drive+.6){let dy=toOm-ty;while(dy>Math.PI)dy-=Math.PI*2;while(dy<-Math.PI)dy+=Math.PI*2;yaw+=clamp(dy,-.6,.6)*smooth(clamp((I.t-(INTRO.drive-4))/1.5,0,1))*.7;}
  const td2=I.t-INTRO.drive-INTRO.drink;let pos=eye;
  if(td2>0){const out=M.apply(tm,[-1.75,1.62,.15]);const k=smooth(clamp((td2-.5)/1.6,0,1));pos=V.lerp(eye,[out[0],G.W.H(out[0],out[2])+1.62,out[2]],k);
    let dy=toOm-yaw;while(dy>Math.PI)dy-=Math.PI*2;while(dy<-Math.PI)dy+=Math.PI*2;yaw+=dy*smooth(clamp((td2-.2)/1.8,0,1));pitch=lerp(pitch,-.05,k);}
  return {eye:pos,yaw,pitch,roll:-tk.roll*.5};}
function startIntro(){sndInit();G.phase='intro';G.introSkip=false;G.intro={t:0,d:0,eng:makeEngine('truck')};placeTruckAt(0);settleTrailer(true);
  $('title').hidden=true;$('hud').hidden=false;$('introHint').hidden=false;$('fade').classList.add('out');}
function endIntro(){const I=G.intro;if(I.eng){I.eng.stop();I.eng=null;}G.truck.door=0;SFX.slam();placeTruckAt(G.pathLen[G.pathLen.length-1]);settleTrailer(false);
  G.truck.canOnSeat=true;const c=introCamera();G.phase='play';$('introHint').hidden=true;$('introCard').classList.remove('on');
  const tm=truckMatrix(),out=M.apply(tm,[-1.75,0,.15]);G.pl.pos=[out[0],G.W.H(out[0],out[2]),out[2]];G.pl.yaw=c.yaw;G.pl.pitch=-.05;G.om.state='wave';
  setTimeout(()=>{if(G.om.state==='wave')G.om.state='idle';},4000);
  toast('Click to look around. Walk with WASD. Talk to Earl with E.',5000);$('objectives').hidden=false;$('hotbar').hidden=false;}

/* ================= rendering ================= */
function render(cam){const r=RD;r.resize();const asp=r.cv.width/r.cv.height;const P=M.persp(1.2,asp,.05,700);const Vw=M.view(cam.eye,cam.yaw,cam.pitch,cam.roll);const VP=M.mul(P,Vw);G.VP=VP;
  r.begin(VP,cam.eye,true);const m=G.meshes;
  r.draw(m.terrain);r.draw(m.roads);drawDust(r);r.draw(m.house);r.draw(m.woods);
  // truck + wheels + door
  const tm=truckMatrix();r.draw(m.truck,tm);
  const stA=G.drive?G.drive.steer:0;for(const [x,z] of [[-TRUCK.track,TRUCK.frontAxle],[TRUCK.track,TRUCK.frontAxle],[-TRUCK.track,TRUCK.rearAxle],[TRUCK.track,TRUCK.rearAxle]])r.draw(m.wheel,M.mul(tm,M.mul(M.T(x*1.05,TRUCK.wheelR,z),M.mul(M.Ry(z>0?stA:0),M.Rx(G.truck.wheel)))));
  r.draw(m.door,M.mul(tm,M.mul(M.T(-.97,0,.78),M.Ry(G.truck.door))));
  if(G.truck.canOnSeat)r.draw(m.can,M.mul(tm,M.mul(M.T(.45,.82,-.32),M.mul(M.Rz(Math.PI/2),M.S(1,.55,1)))));
  // chipper
  const cm=chipMatrix();r.draw(m.chipper,cm);for(const sx of [-1,1])r.draw(m.wheel,M.mul(cm,M.mul(M.T(sx*.78,TRUCK.wheelR-.5+.0,CHIP.axle),M.Rx(G.truck.wheel*0))));
  // tree, stump, pieces
  const tr=G.tree;if(tr.mesh)r.draw(tr.mesh,M.mul(M.QT(tr.q,[tr.x,tr.y0,tr.z]),M.ident()));if(tr.stump)r.draw(tr.stump,M.T(tr.x,tr.y0,tr.z));
  for(const b of PHYS.bodies){if(b.mode==='gone')continue;if(b.mode==='feed'&&b.mb){const fm=RD.upload(foldIntoHopper(b));r.draw(fm);RD.free(fm);continue;}r.draw(b.gpu,bodyMatrix(b));}
  if(G.saw.racked)r.draw(m.saw,M.mul(cm,M.mul(M.T(-.74,.86,-1.78),M.Rz(-.08))));
  if(G.wedge)r.draw(G.wedge.gpu,bodyMatrix(G.wedge.b));
  // old man
  const om=omMatrices();r.draw(m.om_torso,om.torso);r.draw(m.om_head,om.headR);r.draw(m.om_upper,om.uR);r.draw(m.om_fore,om.fR);r.draw(m.om_upper,om.uL);r.draw(m.om_fore,om.fL);r.draw(m.om_leg,om.legL);r.draw(m.om_leg,om.legR);r.draw(m.om_cane,om.cane);
  // soft blob shadows (drawn flat on the ground, blended)
  {const gl=r.gl;gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.depthMask(false);const H=G.W.H;
    const sh=(x,z,sx,sz,yaw,a)=>r.draw(m.shadow,M.mul(M.mul(M.T(x,H(x,z)+.04,z),M.Ry(yaw||0)),M.S(sx,1,sz)),[0,0,0,a||.32]);
    sh(G.truck.pos[0],G.truck.pos[2],1.25,2.9,G.truck.yaw,.38);const cc=M.apply(cm,[0,0,-2.3]);sh(cc[0],cc[2],.8,1.7,G.chip.yaw,.3);
    sh(G.om.x,G.om.z,.38,.38,0,.35);
    if(G.phase==='play'&&!G.pl.inTruck)sh(G.pl.pos[0],G.pl.pos[2],.34,.34,0,.3);
    for(const b of PHYS.bodies){if(b.mode==='gone'||b.round===false&&b.brush)continue;const gh=H(b.pos[0],b.pos[2]);if(b.pos[1]-gh>2)continue;sh(b.pos[0],b.pos[2],Math.min(1.2,b.rad*.7),Math.min(1.2,b.rad*.7),0,.22);}
    gl.depthMask(true);gl.disable(gl.BLEND);}
  // the saw lives in the world: where the bar is inside the wood, the wood hides it
  if(G.phase==='play'&&!G.pl.inTruck&&G.pl.tool==='saw'&&!G.pl.carry&&G.saw.poseW){const sw=G.saw.poseW,CW=G.saw.CW;r.draw(m.saw,sw);
    // right hand on the rear handle (bar runs along the saw's Z), left hand on the top of the wrap handle (bar along X)
    const rH=M.mul(sw,M.mul(M.T(0,.098,.035),M.Ry(Math.PI/2))),lH=M.mul(sw,M.mul(M.T(-.05,.172,-.233),M.Ry(-.3)));r.draw(m.fistR,rH);r.draw(m.fistL,lH);
    drawArm(r,M.apply(rH,[0,.02,.06]),M.apply(CW,[.26,-.55,.12]),.042);drawArm(r,M.apply(lH,[0,.02,.06]),M.apply(CW,[-.42,-.5,.08]),.042);}
  // particles
  if(G.parts.length){const pm=RD.upload(partMesh());r.draw(pm);RD.free(pm);}
  // first-person view model
  drawViewModel(cam);
  // speech bubble over Earl
  const bub=$('bubble');const o=G.om;if(o.bubble&&performance.now()<o.bubbleT){const hp=[o.x,G.W.H(o.x,o.z)+2.05,o.z];const c=M.mul(VP,M.ident());const v=[VP[0]*hp[0]+VP[4]*hp[1]+VP[8]*hp[2]+VP[12],VP[1]*hp[0]+VP[5]*hp[1]+VP[9]*hp[2]+VP[13],VP[3]*hp[0]+VP[7]*hp[1]+VP[11]*hp[2]+VP[15]];
    if(v[2]>.1){bub.hidden=false;bub.textContent=o.bubble;const bw=bub.offsetWidth||200,vw=innerWidth,vh=innerHeight;bub.style.left=clamp((v[0]/v[2]*.5+.5)*vw,bw/2+8,vw-bw/2-8)+'px';bub.style.top=clamp((1-(v[1]/v[2]*.5+.5))*vh,(bub.offsetHeight||60)+8,vh-20)+'px';}else bub.hidden=true;}else bub.hidden=true;}
function drawArm(r,a,b,rad){const d=V.sub(b,a),L=V.len(d);if(L<1e-3)return;const q=Q.between([0,1,0],V.mul(d,1/L));r.draw(G.meshes.arm,M.mul(M.QT(q,a),M.S(rad,L,rad)));}
function drawViewModel(cam){const r=RD,gl=r.gl,m=G.meshes;const asp=r.cv.width/r.cv.height;r.clearDepth();
  const P=M.persp(1.0,asp,.01,10);const Vw=M.view(cam.eye,cam.yaw,cam.pitch,cam.roll);const sunCam=V.norm(M.applyDir(Vw,r.env.sun));const keep=r.env.sun;r.env.sun=sunCam;r.begin(P,[0,0,0],false);r.env.sun=keep;
  gl.uniform2f(r.u.fogR,1e4,2e4);const now=performance.now()/1000;
  if(G.phase==='intro'){const I=G.intro,dt0=I.t-INTRO.drive-.6;if(dt0>4.2)return;
    let pos=[.2,-.3,-.42],rx=0,rz=.15,sc=1;const k1=smooth(clamp(dt0/.8,0,1)),k2=smooth(clamp((dt0-2.6)/.4,0,1));
    pos=V.lerp(pos,[.05,-.11,-.3],k1*(1-k2));rx=lerp(0,1.3,k1*(1-k2)*smooth(clamp((dt0-.3)/.6,0,1)));if(dt0>2.9)sc=lerp(1,.5,clamp((dt0-2.9)/.25,0,1));
    if(dt0>3.6){const k=clamp((dt0-3.6)/.6,0,1);pos=V.lerp([.22,-.28,-.42],[.55,-.5,-.35],k);pos[1]+=Math.sin(k*Math.PI)*.12;rz=lerp(.15,2.5,k);}
    if(dt0<0){pos[1]+=Math.sin(I.t*7)*.004;}
    const Mo=M.mul(M.T(pos[0],pos[1],pos[2]),M.mul(M.Rx(rx),M.mul(M.Rz(rz),M.S(1,sc,1))));r.draw(m.can,M.mul(Mo,M.T(0,-.02,0)));if(dt0<3.6){r.draw(m.handCan,M.mul(M.T(pos[0],pos[1],pos[2]),M.mul(M.Rx(rx),M.mul(M.Rz(rz),M.Ry(-Math.PI/2)))));r.draw(m.forearm,M.T(pos[0],pos[1]-Math.sin(rx)*.03,pos[2]));}return;}
  if(G.phase!=='play'||G.pl.inTruck)return;const p=G.pl;const bobX=Math.sin(p.bob)*.012,bobY=-Math.abs(Math.cos(p.bob))*.012;
  if(p.tool==='saw'&&!p.carry){return;const s=G.saw;let y=-.33,rx=-.06,ry=.1;if(s.pull>0){const k=Math.sin((1-s.pull/.5)*Math.PI);y-=.06*k;rx+=.25*k;}
    const vib=s.on?(s.cutting?.006:.0025):0;const jx=(Math.random()-.5)*vib,jy=(Math.random()-.5)*vib;
    const cutting=s.cutting;const base=M.mul(M.T(.3+bobX+jx,-.36+(y+.33)+bobY+jy+(cutting?.05:0),-.42+(cutting?-.08:0)),M.mul(M.Ry(.55+(cutting?.08:0)),M.mul(M.Rx(.1+(cutting?.06:0)),M.Rz(-.22))));
    r.draw(m.saw,base);r.draw(m.gloveR,M.mul(base,M.mul(M.T(0,.08,.04),M.Rx(.3))));r.draw(m.gloveL,M.mul(base,M.mul(M.T(-.04,.17,-.23),M.mul(M.Ry(.4),M.Rx(.5)))));}
  const hand=(x,y,z,rx)=>{const Mo=M.mul(M.T(x,y,z),M.mul(M.Rx(rx),M.Ry(Math.PI/2)));r.draw(x>0?m.fistR:m.fistL,Mo);drawArm(r,M.apply(Mo,[0,.02,.06]),[x*1.2,-.6,.12],.042);};
  if(p.carry){hand(.24,-.3+bobY,-.55,-.5);hand(-.24,-.3+bobY,-.55,-.5);}
  else{hand(.25+bobX,-.3+bobY,-.5,-.3);hand(-.25-bobX,-.3+bobY,-.5,-.3);}}

/* ================= main loop ================= */
let last=performance.now();
function frame(now){const dt=Math.min(.05,(now-last)/1000);last=now;G.t+=dt;
  try{tick(dt,now);}catch(e){console.error(e);showError(e);return;}
  requestAnimationFrame(frame);}
function tick(dt,now){let cam;
  if(G.phase==='title'){const a=now/1000*.05;const c=[G.W.tree.x,0,G.W.tree.z];cam={eye:[c[0]+Math.sin(a)*45,G.W.H(c[0],c[2])+18,c[2]+Math.cos(a)*45],yaw:a,pitch:-.33,roll:0};}
  else if(G.phase==='intro'){stepIntro(dt);updateOldMan(dt);cam=introCamera();}
  else{if(G.phase==='play'&&G.pl.inTruck){stepDrive(dt);G.aim=null;stepDialog(dt);}
    else if(G.phase==='play'){stepPlayer(dt);G.aim=aimInfo();const pc=G.pl;sawPose({eye:V.add(pc.pos,[0,pc.eyeY||1.62,0]),yaw:pc.yaw,pitch:pc.pitch,roll:0},dt);stepSaw(dt);stepStanding(dt);stepDialog(dt);checkCrush();}
    updateOldMan(dt);const tr=G.tree;
    // physics with the hinge driven in the same sub-steps
    const sub=Math.max(1,Math.round(dt/PHYS.dt));for(let i=0;i<sub;i++){if(tr.state==='hinge')hingeStep(dt/sub);}
    if(G.chip.mode==='hand')settleTrailer(false);updateSolidBoxes();physUpdate(dt,G.W.H,G.stumpCol);if(tr.state==='down')breakUnderLimbs();
    if(tr.state==='down'&&!G.objs.felled&&tr.body&&(tr.body.sleep||performance.now()-tr.downT>6000)){G.objs.felled=true;updateObjectives();SFX.ding();}
    stepFeed(dt);stepParts(dt);
    // saw engine
    const s=G.saw;if(s.pull>0)s.pull=Math.max(0,s.pull-dt);if(s.on){s.rpm=lerp(s.rpm,G.mouse.r?1:.05,Math.min(1,dt*(G.mouse.r?6:3)));if(s.engine)s.engine.set(s.rpm*(s.cutting?.82:1),s.cutting?1:0,.42);}
    const c=G.chip;if(c.engine){c.load=Math.max(0,(c.load||0)-dt*1.5);const d=V.dist(G.pl.pos,c.pos);c.engine.set(.5+c.load*.4,c.load,clamp(1-d/60,.05,1)*.55);}
    const p=G.pl;if(p.inTruck)cam=driveCamera();else cam={eye:V.add(p.pos,[0,(p.eyeY||1.62)+(p.ground?Math.abs(Math.sin(p.bob))*.025:0),0]),yaw:p.yaw,pitch:p.pitch,roll:0};
    if(G.phase==='play')updateHUD();
    if(G.objs.felled&&!G.objs.paid&&now-(G.lastObj||0)>800){G.lastObj=now;updateObjectives();}}
  render(cam);
  if(G.toastT&&now>G.toastT){$('toast').classList.remove('on');G.toastT=0;}}
function updateHUD(){const a=G.aim,p=G.pl;let t='';
  if(p.inTruck){$('prompt').innerHTML='';$('drive').hidden=false;$('drive').innerHTML=`<div><b>W/S</b> drive · <b>A/D</b> steer · <b>Space</b> brake · <b>V</b> camera · <b>E</b> get out</div><span>${Math.abs(G.drive.v*2.237).toFixed(0)} mph</span>`;$('barTilt').hidden=true;$('money').textContent='$'+G.money;return;}
  $('drive').hidden=true;
  if(G.dlg)t='';else if(G.chip.mode==='hand')t=V.dist(couplerWorld(),hitchWorld())<.8?'<b>E</b> Hitch it to the truck':'<b>E</b> Set the tongue down';
  else if(p.carry){const n=p.carryList.length,near=V.dist(hopperWorld(),G.eye)<3.4;const more=a&&a.kind==='body'&&a.b.piece&&canAddCarry(a.b)&&p.tool==='hands';
    t=more?`<b>E</b> Pick up another · ${lb(carryMass()+a.b.m)} total`:(p.carry.brush&&near&&G.chip.running?`<b>E</b> Feed the chipper${n>1?` (${n})`:''}`:`<b>E</b> Drop${n>1?' all':''} · <b>Q</b> drop one`)+` · ${lb(carryMass())}`;}
  else if(a){if(a.kind==='om')t='<b>E</b> Talk to Earl';else if(a.kind==='truck')t='<b>E</b> Get in the truck';else if(a.kind==='tailgate')t=p.onBed?'<b>E</b> Hop down':'<b>E</b> Hop in the back';else if(a.kind==='rack')t=G.saw.racked?'<b>E</b> Take the saw':'<b>E</b> Hang the saw on the rack';else if(a.kind==='hitch')t=G.chip.mode==='truck'?'<b>E</b> Unhitch the chipper':'<b>E</b> Grab the tongue';else if(a.kind==='chipper')t=`<b>E</b> ${G.chip.running?'Stop':'Start'} the chipper`;
    else if(a.kind==='tree')t=p.tool==='saw'?(G.saw.on?'':'<b>R</b> Pull-start the saw'):'Dead white ash';
    else if(a.kind==='body'){const b=a.b;if(p.tool==='saw')t=G.saw.on?'':'<b>R</b> Pull-start the saw';
      else t=!b.piece?'':b.piece.kind==='trunk'&&b.piece.limbs.length?lb(b.m):(b.m>WOOD.liftMax?lb(b.m):`<b>E</b> Pick up ${b.brush?'brush':'round'} · ${lb(b.m)}`);}}
  $('prompt').innerHTML=t;
  const bt=$('barTilt');bt.hidden=p.tool!=='saw';if(!bt.hidden){const deg=Math.round(G.saw.roll*180/Math.PI);bt.querySelector('i').style.transform=`rotate(${90-deg}deg)`;bt.querySelector('span').textContent=`${deg}°`;}
  $('sawState').textContent=p.tool==='saw'?(G.saw.on?'Saw: running':'Saw: off · R to start'):'';
  $('money').textContent='$'+G.money;}
function showError(e){const el=$('err');el.hidden=false;el.textContent='Something broke: '+(e&&e.message||e);}

/* ================= boot ================= */
function boot(){const cv=$('cv');try{RD=new Renderer(cv);}catch(e){showError(e);return;}
  G.money=loadCareer().money;newLevel(1+Math.floor(Math.random()*1e6));
  window.addEventListener('keydown',e=>{if(['Space','ArrowUp','ArrowDown'].includes(e.code))e.preventDefault();onKey(e,true);});window.addEventListener('keyup',e=>onKey(e,false));
  cv.addEventListener('mousedown',e=>{if(G.phase!=='play')return;if(G.dlg){advanceDialog();return;}if(document.pointerLockElement!==cv){cv.requestPointerLock&&cv.requestPointerLock();return;}if(e.button===2)G.mouse.r=true;});
  cv.addEventListener('contextmenu',e=>e.preventDefault());
  window.addEventListener('mouseup',e=>{if(e.button===2)G.mouse.r=false;});
  $('dialog').addEventListener('click',()=>advanceDialog());
  document.addEventListener('mousemove',e=>{if(document.pointerLockElement!==cv||G.phase!=='play'||G.dlg)return;const p=G.pl;if(p.inTruck){const D=G.drive;D.lookYaw=clamp(D.lookYaw-e.movementX*.0022,-2.2,2.2);D.lookPitch=clamp(D.lookPitch-e.movementY*.0022,-.9,.6);return;}const k=G.saw.cut?.25:1;p.yaw-=e.movementX*.0022*k;p.pitch=clamp(p.pitch-e.movementY*.0022*k,-1.45,1.45);});
  window.addEventListener('wheel',e=>{if(G.phase!=='play'||G.pl.tool!=='saw')return;e.preventDefault();const st=Math.PI/12;G.saw.roll=clamp(G.saw.roll+(e.deltaY>0?st:-st),0,Math.PI);},{passive:false});
  document.addEventListener('pointerlockchange',()=>{G.lock=document.pointerLockElement===cv;$('clickHint').hidden=G.lock||G.phase!=='play';if(!G.lock)G.mouse.r=false;});
  $('btnNew').addEventListener('click',()=>{startIntro();});
  $('btnAgain').addEventListener('click',()=>{location.reload();});
  $('btnRetry').addEventListener('click',()=>{$('dead').hidden=true;newLevel(G.seed);G.phase='play';endIntroQuick();});
  $('bankLine').textContent=G.money?`Bank: $${G.money}`:'';
  PHYS.onImpact=(b,v)=>{if(v>4&&performance.now()-(G.lastThud||0)>250){G.lastThud=performance.now();SFX.thud(v);if(b===G.tree.body&&v>6)for(let i=0;i<3;i++)emit(V.add(b.pos,[ (Math.random()-.5)*8,0,(Math.random()-.5)*8]),[0,2,0],8,hex('#6a5a3a'),2.5,1.2,.06);}};
  requestAnimationFrame(frame);}
function endIntroQuick(){G.intro={t:99};G.truck.canOnSeat=true;const tm=truckMatrix(),out=M.apply(tm,[-1.75,0,.15]);G.pl.pos=[out[0],G.W.H(out[0],out[2]),out[2]];G.pl.yaw=G.truck.yaw+Math.PI;G.objs.talk=true;G.om.state='idle';updateObjectives();$('objectives').hidden=false;$('hotbar').hidden=false;}
window.addEventListener('load',boot);
