/* =====================================================================
   Arbor Simulator · world.js
   Random property generation: terrain, road, driveway, house, shed,
   woodpile, background woods, and where the problem tree stands.
   Coordinates: road runs along X on the south edge (−Z); the house sits north.
   ===================================================================== */
'use strict';

const SIDING=['#e9e4d6','#f0e2b0','#b9cbd6','#b8c4a6','#d9c3a0','#cfd2cf','#e6d2c4'];
const ROOFS=['#3d3f42','#4a3a30','#2f3b33','#5a4a3f','#3a3d4a'];
const DOORS=['#8a2a22','#2f4a3a','#1f2326','#3a4a6a','#7a5a2a'];

function makeWorld(seed){
  const R=RNG(seed),s=R()<.5?-1:1;                     // s mirrors the layout left/right
  const nA=noise2(seed),nB=noise2(seed+7);
  const W={seed,s,R,colliders:[],flat:[]};
  W.roadZ=-56;
  // driveway control points from the road to the parking spot
  W.park=[s*4.5,0,-1];
  W.drive=[[s*15,-56],[s*11,-44],[s*7,-28],[s*5,-12],[s*4.5,-1],[s*4.5,3]];
  W.house={x:s*-9,z:12,w:R.range(12,14),d:R.range(8.5,9.5),wall:2.7,rot:0,
    siding:hex(R.pick(SIDING)),roof:hex(R.pick(ROOFS)),door:hex(R.pick(DOORS))};
  W.shed={x:s*-21,z:R.range(16,24),w:3.2,d:2.6};
  W.pile={x:W.shed.x+s*3.4,z:W.shed.z-0.2,w:3.2,d:2.2};   // woodpile drop zone beside the shed
  // ---- terrain height (gentle rolls, flattened around the house, drive and road) ----
  const raw=(x,z)=>(nA(x/38,z/38)-.5)*2.4+(nB(x/11,z/11)-.5)*.5;
  W.flat.push({x:W.house.x,z:W.house.z,r:13},{x:W.shed.x,z:W.shed.z,r:6},{x:W.park[0],z:W.park[2],r:9});
  W.H=(x,z)=>{let h=raw(x,z);const base=raw(W.house.x,W.house.z);
    for(const f of W.flat){const d=Math.hypot(x-f.x,z-f.z);if(d<f.r*1.6){const t=smooth(clamp((f.r*1.6-d)/(f.r*.6),0,1));h=lerp(h,base,t);}}
    const dr=Math.abs(z-W.roadZ);if(dr<9){h=lerp(h,base-.15,smooth(clamp((9-dr)/5,0,1)));}
    return h;};
  // ---- problem tree: open lawn, clear of the house, shed, drive and road by more than its height ----
  W.tree=null;
  for(let k=0;k<400&&!W.tree;k++){const x=R.range(-38,38),z=R.range(-24,40);const ht=R.range(17,20);
    const clear=ht+3.5;
    const dHouse=boxDist(x,z,W.house), dShed=boxDist(x,z,W.shed), dPile=Math.hypot(x-W.pile.x,z-W.pile.z), dPark=Math.hypot(x-W.park[0],z-W.park[2]);
    const dDrive=Math.min(...W.drive.map(p=>Math.hypot(x-p[0],z-p[1])));
    if(dHouse<clear||dShed<clear||dPile<clear-1||dPark<clear+4||dDrive<clear-2||z-W.roadZ<clear+4)continue;
    W.tree={x,z,h:ht,dbh:R.range(.5,.6),lean:R.range(.02,.06),leanDir:R.range(0,Math.PI*2),seed:R.int(1,1e6)};}
  if(!W.tree)W.tree={x:s*24,z:30,h:16,dbh:.5,lean:.04,leanDir:1,seed:5};
  // ---- old man waits by the parking spot ----
  W.oldMan={x:W.park[0]-s*3.2,z:W.park[2]+4.5};
  W.porch=[W.house.x+W.house.w*.18,W.house.z-W.house.d/2-1.4];
  // ---- static colliders (2D, for the player) ----
  W.colliders.push({t:'box',x:W.house.x,z:W.house.z,hx:W.house.w/2,hz:W.house.d/2});
  W.colliders.push({t:'box',x:W.shed.x,z:W.shed.z,hx:W.shed.w/2,hz:W.shed.d/2});
  W.mailbox=[W.drive[0][0]+s*2.4,W.roadZ+3.2];W.colliders.push({t:'circle',x:W.mailbox[0],z:W.mailbox[1],r:.2});
  // ---- background woods positions ----
  W.bgTrees=[];
  for(let k=0;k<900;k++){const x=R.range(-150,150),z=R.range(-140,150);
    const inside=Math.abs(x)<48&&z>-46&&z<54;const nearRoad=Math.abs(z-W.roadZ)<10;if(inside||nearRoad)continue;
    if(Math.hypot(x,z)>175)continue;W.bgTrees.push({x,z,h:R.range(11,22),kind:R()<.35?'pine':'hard',r:R.range(2.4,4.2),c:R()});}
  // a few yard trees well away from the work area
  W.yardTrees=[];for(let k=0;k<60&&W.yardTrees.length<5;k++){const x=R.range(-44,44),z=R.range(-40,50);
    if(Math.hypot(x-W.tree.x,z-W.tree.z)<W.tree.h+8||boxDist(x,z,W.house)<5||boxDist(x,z,W.shed)<5||Math.hypot(x-W.park[0],z-W.park[2])<12||Math.min(...W.drive.map(p=>Math.hypot(x-p[0],z-p[1])))<6||z-W.roadZ<8)continue;
    W.yardTrees.push({x,z,h:R.range(6,10),kind:R()<.5?'pine':'hard',r:R.range(1.6,2.6),c:R()});W.colliders.push({t:'circle',x,z,r:.35});}
  // the ground everything stands on is exactly the ground that gets drawn: the terrain mesh's own triangles
  W.Hs=W.H;const N=140,S=300,st=S/N,G0=new Float32Array((N+1)*(N+1));for(let j=0;j<=N;j++)for(let i=0;i<=N;i++)G0[j*(N+1)+i]=W.Hs(-S/2+i*st,-S/2+j*st);
  W.H=(x,z)=>{const gx=clamp((x+S/2)/st,0,N-1e-6),gz=clamp((z+S/2)/st,0,N-1e-6),i=Math.floor(gx),j=Math.floor(gz),fx=gx-i,fz=gz-j;
    const A=G0[j*(N+1)+i],B=G0[(j+1)*(N+1)+i],C=G0[(j+1)*(N+1)+i+1],D=G0[j*(N+1)+i+1];
    return fz>fx?A+(C-B)*fx+(B-A)*fz:A+(D-A)*fx+(C-D)*fz;};
  return W;
}
function boxDist(x,z,b){const dx=Math.max(Math.abs(x-b.x)-b.w/2,0),dz=Math.max(Math.abs(z-b.z)-b.d/2,0);return Math.hypot(dx,dz);}

/* ---------- smooth path through control points (Catmull-Rom) ---------- */
function spline(pts,n){const out=[];for(let i=0;i<pts.length-1;i++){const p0=pts[Math.max(0,i-1)],p1=pts[i],p2=pts[i+1],p3=pts[Math.min(pts.length-1,i+2)];
  for(let k=0;k<n;k++){const t=k/n,t2=t*t,t3=t2*t;const f=(a,b,c,d)=>.5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t2+(-a+3*b-3*c+d)*t3);out.push([f(p0[0],p1[0],p2[0],p3[0]),f(p0[1],p1[1],p2[1],p3[1])]);}}
  out.push(pts[pts.length-1].slice());return out;}

/* ---------- terrain + roads ---------- */
function buildTerrain(W){const mb=new MeshB(),N=140,S=300,st=S/N,H=W.H;const nC=noise2(W.seed+3);
  const lawn=hex('#5f8a3a'),lawn2=hex('#6f9a44'),meadow=hex('#7d8a45'),forest=hex('#4a5a30'),dirt=hex('#7a6a4a');
  const col=(x,z)=>{const inside=Math.abs(x)<46&&z>-48&&z<52;const n=nC(x/6,z/6);let c=inside?mixc(lawn,lawn2,n):mixc(meadow,forest,clamp((Math.abs(x)-46)/14,0,1)*.7+n*.3);
    if(!inside&&(Math.abs(x)>60||z>66))c=mixc(c,forest,.6);
    // mowing stripes on the lawn
    if(inside)c=shade(c,(Math.floor((x+z*.15)/2.2)%2)?1.04:.96);
    return c;};
  const idx=[];for(let j=0;j<=N;j++){const row=[];for(let i=0;i<=N;i++){const x=-S/2+i*st,z=-S/2+j*st,y=H(x,z);
    const e=.6,nx=H(x-e,z)-H(x+e,z),nz=H(x,z-e)-H(x,z+e);row.push(mb.v([x,y,z],V.norm([nx,2*e,nz]),col(x,z)));}idx.push(row);}
  for(let j=0;j<N;j++)for(let i=0;i<N;i++)mb.quad(idx[j][i],idx[j+1][i],idx[j+1][i+1],idx[j][i+1]);
  return mb;}
// a ribbon draped on the terrain along a path
function ribbon(mb,W,path,width,col,lift,edgeCol){const H=W.H;const L=[],Rr=[];
  for(let k=0;k<path.length;k++){const a=path[Math.max(0,k-1)],b=path[Math.min(path.length-1,k+1)];const dx=b[0]-a[0],dz=b[1]-a[1],l=Math.hypot(dx,dz)||1;const nx=-dz/l,nz=dx/l;const p=path[k];
    const lp=[p[0]+nx*width/2,0,p[1]+nz*width/2],rp=[p[0]-nx*width/2,0,p[1]-nz*width/2];lp[1]=H(lp[0],lp[2])+lift;rp[1]=H(rp[0],rp[2])+lift;
    const jit=W.R?shade(col,.94+((k*7)%5)*.025):col;L.push(mb.v(lp,[0,1,0],edgeCol||jit));Rr.push(mb.v(rp,[0,1,0],edgeCol||jit));}
  for(let k=0;k<path.length-1;k++)mb.quad(L[k],Rr[k],Rr[k+1],L[k+1]);}
function buildRoads(W){const mb=new MeshB();
  const road=[];for(let x=-150;x<=150;x+=3)road.push([x,W.roadZ]);
  ribbon(mb,W,road,7,hex('#3b3d40'),.05);
  // faded yellow centre line (dashed)
  for(let x=-150;x<150;x+=6){const seg=[[x,W.roadZ],[x+3,W.roadZ]];ribbon(mb,W,seg,.14,hex('#c9a640'),.07);}
  // gravel driveway
  const dp=spline(W.drive.map(p=>[p[0],p[1]]),6);W.drivePath=dp;
  ribbon(mb,W,dp,3.4,hex('#8f8676'),.06);
  // gravel speckles
  const R=RNG(W.seed+11);for(let k=0;k<dp.length-1;k++)for(let m=0;m<6;m++){const t=R(),a=dp[k],b=dp[k+1];const x=lerp(a[0],b[0],t)+R.range(-1.5,1.5),z=lerp(a[1],b[1],t)+R.range(-1.5,1.5);const y=W.H(x,z)+.07;
    mb.box(x,y,z,R.range(.08,.18),.02,R.range(.08,.18),shade(hex('#8f8676'),R.range(.75,1.2)));}
  return mb;}

/* ---------- house ---------- */
function buildHouse(W){const mb=new MeshB(),h=W.house,y0=W.H(h.x,h.z),R=RNG(W.seed+21);
  const trim=hex('#f2f0ea'),glass=hex('#2c3a46'),found=hex('#8b8a86'),sid=h.siding;
  mb.push(M.T(h.x,y0,h.z));
  mb.box(0,.2,0,h.w+.1,.5,h.d+.1,found);                               // foundation
  // lap siding: stacked boards in slightly different shades
  const boards=14;for(let b=0;b<boards;b++){const yy=.45+b*(h.wall/boards);mb.box(0,yy+h.wall/boards/2,0,h.w+(b%2?.02:0),h.wall/boards,h.d+(b%2?.02:0),shade(sid,b%2?.96:1.02));}
  const top=.45+h.wall;
  // gable roof along X
  const ov=.5,rh=2.3,hw=h.w/2+ov,hd=h.d/2+ov;const roof=h.roof;
  mb.face([[-hw,top-.05,-hd],[hw,top-.05,-hd],[hw,top+rh,0],[-hw,top+rh,0]].reverse(),roof);
  mb.face([[-hw,top-.05,hd],[-hw,top+rh,0],[hw,top+rh,0],[hw,top-.05,hd]].reverse(),shade(roof,.92));
  // gable ends (siding triangles)
  for(const sx of [-1,1]){const x=sx*h.w/2;const a=mb.v([x,top,-h.d/2],[sx,0,0],sid),b=mb.v([x,top,h.d/2],[sx,0,0],sid),c=mb.v([x,top+rh-.35,0],[sx,0,0],sid);mb.tri(a,b,c);mb.tri(a,c,b);}
  // fascia trim
  mb.box(0,top-.1,-hd,h.w+2*ov,.18,.06,trim);mb.box(0,top-.1,hd,h.w+2*ov,.18,.06,trim);
  // windows on front and back
  const win=(x,z,face)=>{mb.box(x,1.75,z,1.3,1.2,.08,trim);mb.box(x,1.75,z+face*.03,1.1,1.0,.06,glass);mb.box(x,1.75,z+face*.05,.05,1.0,.02,trim);mb.box(x,1.75,z+face*.05,1.1,.05,.02,trim);
    mb.box(x-.85,1.75,z,.35,1.2,.05,shade(h.door,.9));mb.box(x+.85,1.75,z,.35,1.2,.05,shade(h.door,.9));};   // shutters
  const fz=-h.d/2-.04,bz=h.d/2+.04;
  win(-h.w*.32,fz,-1);win(h.w*.36,fz,-1);win(-h.w*.3,bz,1);win(h.w*.05,bz,1);win(h.w*.35,bz,1);
  // side windows
  for(const sx of [-1,1]){mb.box(sx*(h.w/2+.04),1.75,0,.08,1.1,1.1,trim);mb.box(sx*(h.w/2+.07),1.75,0,.06,.92,.92,glass);}
  // front door + porch
  const dx=h.w*.18;mb.box(dx,1.5,fz-.02,1.1,2.25,.1,trim);mb.box(dx,1.47,fz-.06,.92,2.1,.06,h.door);mb.box(dx+.32,1.45,fz-.11,.07,.07,.07,hex('#c9a640'));
  mb.box(dx,.28,fz-1.3,3.2,.32,2.4,hex('#9a958c'));                 // porch slab
  mb.box(dx,.06,fz-2.8,1.4,.18,.6,hex('#9a958c'));                   // step
  for(const px of [-1.4,1.4])mb.box(dx+px,1.75,fz-2.35,.14,2.6,.14,trim);
  mb.push(M.T(dx,top+.15,fz-1.25));mb.face([[-1.8,0,-1.3],[1.8,0,-1.3],[1.8,.55,.1],[-1.8,.55,.1]].reverse(),roof);mb.pop();
  // brick chimney
  const cx=-h.w*.3;for(let r=0;r<12;r++)mb.box(cx,top+.2+r*.25,h.d*.18,.8,.25,.8,shade(hex('#8a4a36'),r%2?.92:1.05));
  mb.box(cx,top+3.25,h.d*.18,.9,.1,.9,hex('#5a5a5a'));
  // a couple of shrubs along the front
  for(let k=0;k<5;k++){const x=-h.w/2+1+k*(h.w-2)/4;if(Math.abs(x-dx)<2)continue;mb.blob(x,.55,fz-.8,.65,hex('#3f6a2e'),R,.8);}
  mb.pop();
  // shed
  const sh=W.shed,sy=W.H(sh.x,sh.z);mb.push(M.T(sh.x,sy,sh.z));
  const sc=shade(sid,.9);mb.box(0,1.1,0,sh.w,2.2,sh.d,sc,[sc,sc,sc,sc,shade(sc,.95),shade(sc,.95)]);
  for(let k=0;k<7;k++)mb.box(-sh.w/2+.25+k*(sh.w-.5)/6,1.1,-sh.d/2-.02,.04,2.2,.03,shade(sc,.8));
  mb.push(M.T(0,2.2,0));mb.face([[-sh.w/2-.3,0,-sh.d/2-.3],[sh.w/2+.3,0,-sh.d/2-.3],[sh.w/2+.3,.9,0],[-sh.w/2-.3,.9,0]].reverse(),roof);mb.face([[-sh.w/2-.3,0,sh.d/2+.3],[-sh.w/2-.3,.9,0],[sh.w/2+.3,.9,0],[sh.w/2+.3,0,sh.d/2+.3]].reverse(),roof);
  for(const sx of [-1,1]){const x=sx*sh.w/2;const a=mb.v([x,0,-sh.d/2],[sx,0,0],sc),b=mb.v([x,0,sh.d/2],[sx,0,0],sc),c=mb.v([x,.85,0],[sx,0,0],sc);mb.tri(a,b,c);mb.tri(a,c,b);}
  mb.pop();mb.box(0,1,-sh.d/2-.06,1.1,1.9,.04,shade(sc,.7));mb.pop();
  // woodpile area: pallet + a few old split pieces + stakes with orange flagging
  const p=W.pile,py=W.H(p.x,p.z);mb.push(M.T(p.x,py,p.z));
  const wood=hex('#a88a62');for(let k=0;k<5;k++)mb.box(-p.w/2+.2+k*(p.w-.4)/4,.12,0,.14,.04,p.d,wood);for(const z of [-p.d/2+.1,0,p.d/2-.1])mb.box(0,.05,z,p.w,.1,.12,shade(wood,.85));
  for(let k=0;k<6;k++){const x=-p.w/2+.6+(k%3)*.5,z=p.d/2-.25-Math.floor(k/3)*.3;mb.push(M.T(x,.32,z));mb.tf(M.Rx(Math.PI/2));mb.cyl(0,-.2,0,.12,.12,.4,hex('#7a5a3a'),6,true,hex('#c9a878'));mb.pop();}
  for(const [x,z] of [[-p.w/2,-p.d/2],[p.w/2,-p.d/2],[p.w/2,p.d/2],[-p.w/2,p.d/2]]){mb.box(x,.45,z,.05,.9,.05,hex('#c9a878'));mb.box(x,.82,z,.07,.14,.02,hex('#ff6a1a'));}
  mb.pop();
  // mailbox
  const [mx,mz]=W.mailbox,my=W.H(mx,mz);mb.box(mx,my+.55,mz,.08,1.1,.08,hex('#6a5a44'));mb.push(M.T(mx,my+1.18,mz));mb.tf(M.Rx(Math.PI/2));mb.cyl(0,-.25,0,.12,.12,.5,hex('#2a2d30'),10,true);mb.pop();mb.box(mx+.14,my+1.28,mz-.1,.02,.2,.06,hex('#c03a2a'));
  return mb;}

/* ---------- background woods and yard trees (one merged mesh) ---------- */
function buildWoods(W){const mb=new MeshB(),R=RNG(W.seed+31);
  const bark=hex('#4a3e34'),leaf=[hex('#3c6a2a'),hex('#4f7a32'),hex('#5c7f36'),hex('#46682c')],pine=[hex('#2c4a2c'),hex('#355434'),hex('#2a4430')];
  const one=(t,lod)=>{const y=W.H(t.x,t.z);if(t.kind==='pine'){mb.cyl(t.x,y,t.z,.22,.12,t.h*.35,bark,5,false);const tiers=lod?3:4;
      for(let k=0;k<tiers;k++){const f=k/tiers;const r=t.r*(1-f*.72),y0=y+t.h*(.2+f*.62);mb.cyl(t.x,y0,t.z,r,.02,t.h*(.42-f*.06),pine[k%3],lod?6:8,false);}}
    else{mb.cyl(t.x,y,t.z,.26,.14,t.h*.6,bark,5,false);const c=leaf[Math.floor(t.c*4)%4];const n=lod?2:4;
      for(let k=0;k<n;k++)mb.blob(t.x+R.range(-1,1)*t.r*.5,y+t.h*R.range(.62,.84),t.z+R.range(-1,1)*t.r*.5,t.r*R.range(.7,1),c,R,.85);}};
  for(const t of W.bgTrees)one(t,Math.hypot(t.x,t.z)>90);
  for(const t of W.yardTrees)one(t,false);
  return mb;}
