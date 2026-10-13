/* =====================================================================
   Arbor Simulator · tree.js
   The problem tree: a dead white ash (emerald ash borer) with bare limbs.
   Everything is described in the tree's "wood frame": origin at the base
   of the trunk on the ground, +Y up the stem. Pieces (the felled stem,
   limbs, rounds) keep wood-frame coordinates so they can be split freely.
   ===================================================================== */
'use strict';

const WOOD={rho:640,liftMax:60,chipR:.095,brushR:.07,cutSpeed:.11,limbCutSpeed:.16};

function cylI(m,r,l,a){const ia=m*r*r/2,ip=m*(3*r*r+l*l)/12;const I=[];for(let i=0;i<3;i++)for(let j=0;j<3;j++)I.push(ip*((i===j?1:0)-a[i]*a[j])+ia*a[i]*a[j]);return I;}

function makeTreeDef(t){const R=RNG(t.seed),H=t.h;
  const shape=y=>Math.pow(Math.max(0,1-y/H),.85)*(1+.38*Math.exp(-Math.max(y,0)/.35));
  const k=(t.dbh/2)/shape(1.37);const rAt=y=>Math.max(.018,k*shape(clamp(y,0,H)));
  const T={H,dbh:t.dbh,rAt,cb:H*R.range(.38,.46),limbs:[],seed:t.seed};
  const n=R.int(9,12);
  for(let i=0;i<n;i++){const f=(i+R.range(.1,.9))/n;const y=T.cb+f*(H*.9-T.cb);const az=i*2.39996+R.range(-.4,.4);const el=lerp(.42,1.05,f)+R.range(-.15,.15);
    const dir=V.norm([Math.cos(az)*Math.cos(el),Math.sin(el),Math.sin(az)*Math.cos(el)]);
    const len=clamp((H-y)*.5+R.range(1.2,2.4),1.6,5.6),r0=Math.min(.085,rAt(y)*R.range(.45,.6));
    const base=V.add([0,y,0],V.mul([dir[0],0,dir[2]],rAt(y)*.6));
    const subs=[];const ns=R.int(2,3);for(let s=0;s<ns;s++){const tt=R.range(.3,.78);const side=R.range(-1,1)>0?1:-1;
      const ax=V.norm(V.cross(dir,[0,1,0]));const sd=V.norm(V.add(V.add(dir,V.mul(ax,side*R.range(.5,.9))),[0,R.range(.2,.6),0]));
      subs.push({t:tt,dir:sd,len:len*R.range(.3,.48),r0:r0*(1-.7*tt)*.75});}
    T.limbs.push({id:i,y,dir,len,r0,base,subs,on:true});}
  return T;}
const limbPt=(L,t)=>V.add(L.base,V.mul(L.dir,L.len*t));
const limbR=(L,t)=>L.r0*(1-.72*t);

/* ---------- mass samples, contact points and capsules for a piece ---------- */
function pieceGeom(T,P){const S=[],pts=[],caps=[];const rho=WOOD.rho;
  if(P.kind==='trunk'){const L=P.y1-P.y0,n=Math.max(1,Math.ceil(L/.25));
    for(let i=0;i<n;i++){const a=P.y0+i*L/n,b=P.y0+(i+1)*L/n,r=T.rAt((a+b)/2),l=b-a,m=rho*Math.PI*r*r*l;S.push({p:[0,(a+b)/2,0],m,I:cylI(m,r,l,[0,1,0])});}
    const nr=Math.max(2,Math.ceil(L/.45));for(let i=0;i<=nr;i++){const y=P.y0+i*L/nr,r=T.rAt(y);for(let k=0;k<8;k++){const a=k/8*Math.PI*2;pts.push([Math.cos(a)*r,y,Math.sin(a)*r]);}}
    const nc=Math.max(1,Math.ceil(L/1.0));for(let i=0;i<nc;i++){const a=P.y0+i*L/nc,b=P.y0+(i+1)*L/nc;caps.push({a:[0,a,0],b:[0,b,0],r:T.rAt((a+b)/2),trunk:true});}}
  const limbs=P.kind==='trunk'?P.limbs.map(id=>T.limbs[id]):[T.limbs[P.limb]];
  for(const Lm of limbs){const n=4;for(let i=0;i<n;i++){const t0=i/n,t1=(i+1)/n,r=limbR(Lm,(t0+t1)/2),l=Lm.len/n,m=rho*Math.PI*r*r*l;S.push({p:limbPt(Lm,(t0+t1)/2),m,I:cylI(m,r,l,Lm.dir)});}
    for(const t of [.35,.7,1])pts.push(limbPt(Lm,t));
    caps.push({a:limbPt(Lm,0),b:limbPt(Lm,1),r:limbR(Lm,.4)*1.15,limb:Lm.id});
    for(const sb of Lm.subs){const o=limbPt(Lm,sb.t),e=V.add(o,V.mul(sb.dir,sb.len)),m=rho*Math.PI*sb.r0*sb.r0*.4*sb.len;S.push({p:V.lerp(o,e,.5),m,I:cylI(m,sb.r0,sb.len,sb.dir)});pts.push(e);
      caps.push({a:o,b:e,r:sb.r0*.9,limb:Lm.id});}}
  return {S,pts,caps};}

/* ---------- mesh for a piece (or the whole standing tree) ---------- */
const BARK=hex('#7c766c'),BARK_D=hex('#58534b'),BLOND=hex('#c4ae88'),SAP=hex('#e6d3a6'),HEART=hex('#c8ad78'),KERF=hex('#2a2016');
function barkCol(T,y,a,cut){const n=Math.sin(a*7+y*9.3)*Math.sin(a*3-y*13.1);let c=n>.25?BARK_D:BARK;
  const bl=Math.sin(a*2+y*1.7+T.seed)*Math.sin(y*.9-T.seed*.3);if(y>3&&bl>.55)c=mixc(c,BLOND,.8);return cut?SAP:c;}
function addEndCap(mb,T,y,r,up,seg){const cc=mb.v([0,y,0],[0,up,0],HEART);let prev=null;const rings=[.35,.7,1],cols=[HEART,shade(HEART,1.08),SAP];
  let inner=[cc];for(let ri=0;ri<rings.length;ri++){const ring=[];for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;ring.push(mb.v([Math.cos(a)*r*rings[ri],y,Math.sin(a)*r*rings[ri]],[0,up,0],ri===1?shade(cols[ri],.9):cols[ri]));}
    for(let s=0;s<seg;s++){if(inner.length===1){if(up>0)mb.tri(cc,ring[s+1],ring[s]);else mb.tri(cc,ring[s],ring[s+1]);}else{if(up>0)mb.quad(inner[s],inner[s+1],ring[s+1],ring[s]);else mb.quad(inner[s],ring[s],ring[s+1],inner[s+1]);}}inner=ring;}
  // bark rim
  const rim=[];for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;rim.push(mb.v([Math.cos(a)*r*1.03,y,Math.sin(a)*r*1.03],[0,up,0],BARK_D));}for(let s=0;s<seg;s++)mb.quad(inner[s],inner[s+1],rim[s+1],rim[s]);}
function buildPieceMesh(T,P,cuts){const mb=new MeshB(),seg=16;
  if(P.kind==='trunk'){
    // ring heights
    const ys=[];for(let y=P.y0;y<P.y1;y+=.3)ys.push(y);ys.push(P.y1);
    const N=cuts&&cuts.notch&&cuts.notch.depth>0?cuts.notch:null,Bk=cuts&&cuts.back&&cuts.back.depth>0?cuts.back:null;
    if(N){for(let k=-1;k<=8;k++)ys.push(N.h+k*N.depth/8-(k===-1?.002:0));}
    if(Bk){ys.push(Bk.h-.006,Bk.h,Bk.h+.006);}
    const Y=[...new Set(ys.map(y=>+y.toFixed(4)))].filter(y=>y>=P.y0&&y<=P.y1).sort((a,b)=>a-b);
    const rows=[];for(const y of Y){const r=T.rAt(y),row=[];
      for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;let x=Math.cos(a)*r,z=Math.sin(a)*r,cut=false,col=null;
        if(N&&y>=N.h&&y<=N.h+N.depth+1e-4){const sp=x*N.dx+z*N.dz,smax=(r-N.depth)+(y-N.h);if(sp>smax){x-=N.dx*(sp-smax);z-=N.dz*(sp-smax);cut=true;}}
        if(Bk&&Math.abs(y-Bk.h)<1e-4){const sp=-(x*Bk.dx+z*Bk.dz);if(sp>r-Bk.depth){x*=.94;z*=.94;col=KERF;}}
        row.push(mb.v([x,y,z],V.norm([Math.cos(a),.1,Math.sin(a)]),col||barkCol(T,y,a,cut)));}rows.push(row);}
    for(let j=0;j<rows.length-1;j++)for(let s=0;s<seg;s++)mb.quad(rows[j][s],rows[j][s+1],rows[j+1][s+1],rows[j+1][s]);
    if(P.y0>0.01||P.cutBottom)addEndCap(mb,T,P.y0,T.rAt(P.y0),-1,seg);
    if(P.y1<T.H-.02)addEndCap(mb,T,P.y1,T.rAt(P.y1),1,seg);else mb.sphere(0,P.y1,0,T.rAt(P.y1),.04,T.rAt(P.y1),BARK,6,3);
    // limb stubs where limbs were cut off
    for(const id of (P.stubs||[])){const L=T.limbs[id];if(L.y<P.y0||L.y>P.y1)continue;const a=L.base,b=V.add(L.base,V.mul(L.dir,.06));mb.tube(a,b,L.r0*1.05,L.r0,BARK,7,true,SAP);}
  }
  const limbs=P.kind==='trunk'?P.limbs.map(id=>T.limbs[id]):[T.limbs[P.limb]];const R=RNG(T.seed+7);
  for(const L of limbs){const pts=[0,.25,.5,.75,1];for(let i=0;i<pts.length-1;i++){const t0=pts[i],t1=pts[i+1];
      const bend=(t)=>V.add(limbPt(L,t),[0,-Math.sin(t*Math.PI)*L.len*.05,0]);mb.tube(bend(t0),bend(t1),limbR(L,t0),limbR(L,t1),i%2?BARK:shade(BARK,.92),7,i===0&&P.kind==='limb',SAP);}
    for(const sb of L.subs){const o=limbPt(L,sb.t);o[1]-=Math.sin(sb.t*Math.PI)*L.len*.05;const e=V.add(o,V.mul(sb.dir,sb.len));mb.tube(o,e,sb.r0,sb.r0*.35,BARK,5);
      for(let k=0;k<3;k++){const tt=R.range(.4,1),tp=V.lerp(o,e,tt);const d=V.norm(V.add(sb.dir,[R.range(-.8,.8),R.range(0,.6),R.range(-.8,.8)]));mb.tube(tp,V.add(tp,V.mul(d,R.range(.3,.7))),sb.r0*.35,.006,shade(BARK,1.1),4);}}
    const tip=limbPt(L,1);for(let k=0;k<4;k++){const d=V.norm(V.add(L.dir,[R.range(-.9,.9),R.range(-.2,.7),R.range(-.9,.9)]));mb.tube(tip,V.add(tip,V.mul(d,R.range(.4,.9))),limbR(L,1)*.8,.006,shade(BARK,1.08),4);}}
  return mb;}
function buildStumpMesh(T,h,barber){const mb=new MeshB(),seg=16;const rows=[];for(const y of [-.35,0,h*.5,h]){const r=T.rAt(Math.max(y,0)),row=[];for(let s=0;s<=seg;s++){const a=s/seg*Math.PI*2;row.push(mb.v([Math.cos(a)*r,y,Math.sin(a)*r],[Math.cos(a),0,Math.sin(a)],barkCol(T,y,a)));}rows.push(row);}
  for(let j=0;j<rows.length-1;j++)for(let s=0;s<seg;s++)mb.quad(rows[j][s],rows[j][s+1],rows[j+1][s+1],rows[j+1][s]);
  addEndCap(mb,T,h,T.rAt(h),1,seg);
  if(barber){const d=barber;// a tall split slab left standing on the back side
    const r=T.rAt(h);mb.push(M.T(-d.dx*r*.55,h,-d.dz*r*.55));mb.tf(M.Ry(Math.atan2(d.dx,d.dz)));mb.box(0,.8,0,r*1.3,1.6,r*.5,SAP);mb.box(0,.8,-r*.26,r*1.32,1.6,.02,BARK);mb.pop();}
  return mb;}
