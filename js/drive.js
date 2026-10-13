/* =====================================================================
   Arbor Simulator · drive.js
   Driving the truck with the chipper in tow, and limbs that snap under
   the weight of a felled stem.
   ===================================================================== */
'use strict';

const DRV={wheelbase:3.2,maxF:7.5,maxR:3,acc:3.2,brake:7,steerMax:.6};

/* ---------- truck pose from position + heading, following the ground ---------- */
function truckSetPose(x,z,yaw){const W=G.W,tk=G.truck;tk.yaw=yaw;
  const f=[Math.sin(yaw),0,Math.cos(yaw)],r=[Math.cos(yaw),0,-Math.sin(yaw)];
  const hF=W.H(x+f[0]*1.6,z+f[2]*1.6),hB=W.H(x-f[0]*1.6,z-f[2]*1.6),hL=W.H(x-r[0]*.8,z-r[2]*.8),hR=W.H(x+r[0]*.8,z+r[2]*.8);
  tk.pitch=Math.atan2(hF-hB,3.2);tk.roll=Math.atan2(hL-hR,1.6);tk.pos=[x,(hF+hB)/2,z];}

/* ---------- 2D oriented boxes (separating axis test) ---------- */
function obb(cx,cz,yaw,hx,hz){const c=Math.cos(yaw),s=Math.sin(yaw);return {c:[cx,cz],ax:[[c,-s],[s,c]],h:[hx,hz]};}   // ax[0] = local x, ax[1] = local z (world xz)
function obbHit(A,B){const axes=[A.ax[0],A.ax[1],B.ax[0],B.ax[1]];const d=[B.c[0]-A.c[0],B.c[1]-A.c[1]];
  for(const a of axes){const pr=(O)=>O.h[0]*Math.abs(O.ax[0][0]*a[0]+O.ax[0][1]*a[1])+O.h[1]*Math.abs(O.ax[1][0]*a[0]+O.ax[1][1]*a[1]);
    if(Math.abs(d[0]*a[0]+d[1]*a[1])>pr(A)+pr(B))return false;}return true;}
function obbCircle(A,x,z,r){const d=[x-A.c[0],z-A.c[1]];const lx=d[0]*A.ax[0][0]+d[1]*A.ax[0][1],lz=d[0]*A.ax[1][0]+d[1]*A.ax[1][1];
  const qx=clamp(lx,-A.h[0],A.h[0]),qz=clamp(lz,-A.h[1],A.h[1]);return Math.hypot(lx-qx,lz-qz)<r;}
// the truck's yaw turns local +z toward world (sin yaw, cos yaw); local x is (cos yaw, −sin yaw)
function truckBox(x,z,yaw){const b=obb(x,z,0,1.05,2.75);const c=Math.cos(yaw),s=Math.sin(yaw);b.ax=[[c,-s],[s,c]];return b;}
function chipBox(){const m=chipMatrix(),cc=M.apply(m,[0,0,-2.3]);const c=Math.cos(G.chip.yaw),s=Math.sin(G.chip.yaw);const b=obb(cc[0],cc[2],0,.7,1.75);b.ax=[[c,-s],[s,c]];return b;}
function vehicleBlocked(boxes){const W=G.W,tr=G.tree;
  for(const B of boxes){
    for(const c of W.colliders){if(c.t==='box'){if(obbHit(B,obb(c.x,c.z,0,c.hx,c.hz)))return 'building';}else if(obbCircle(B,c.x,c.z,c.r))return 'tree';}
    if(tr.state==='stand'&&obbCircle(B,tr.x,tr.z,tr.T.rAt(.5)))return 'tree';
    if(tr.stumpH>.05&&obbCircle(B,tr.x,tr.z,tr.T.rAt(.5)))return 'stump';
    if(obbCircle(B,G.om.x,G.om.z,.4))return 'earl';
    if(Math.abs(B.c[0])>140||B.c[1]<-120||B.c[1]>140)return 'edge';}
  return null;}

/* ---------- getting in and out ---------- */
function nearDriverDoor(){const d=M.apply(truckMatrix(),[-1.05,1.1,.2]);const e=G.eye||V.add(G.pl.pos,[0,1.6,0]);const to=V.sub(d,e),dist=V.len(to);return dist<2.2&&V.dot(V.norm(to),G.fwd||[0,0,-1])>.6;}
function enterTruck(){const p=G.pl;if(p.carry)dropCarry();if(G.saw.on)sawOff();G.drive={v:0,steer:0,lookYaw:0,lookPitch:-.05,chase:false,eng:makeEngine('truck'),door:0};
  p.inTruck=true;SFX.door();setTimeout(()=>SFX.slam(),350);$('hotbar').hidden=true;}
function exitTruck(){const D=G.drive,p=G.pl;if(Math.abs(D.v)>1){toast('Stop first.');return;}
  const tm=truckMatrix();let out=M.apply(tm,[-1.75,0,.15]);
  // if the driver's side is blocked, climb out the passenger side
  const blocked=(x,z)=>G.W.colliders.some(c=>c.t==='box'?Math.abs(x-c.x)<c.hx+.4&&Math.abs(z-c.z)<c.hz+.4:Math.hypot(x-c.x,z-c.z)<c.r+.4);
  if(blocked(out[0],out[2]))out=M.apply(tm,[1.75,0,.15]);
  p.pos=[out[0],G.W.H(out[0],out[2]),out[2]];p.yaw=G.truck.yaw+Math.PI+D.lookYaw;p.pitch=D.lookPitch;p.inTruck=false;
  if(D.eng)D.eng.stop();G.drive=null;SFX.door();setTimeout(()=>SFX.slam(),300);$('hotbar').hidden=false;}

/* ---------- driving ---------- */
function stepDrive(dt){const D=G.drive,K=G.keys,tk=G.truck;if(!D)return;
  const fwdKey=K.KeyW||K.ArrowUp,backKey=K.KeyS||K.ArrowDown;
  if(fwdKey){D.v=D.v<-.05?Math.min(0,D.v+DRV.brake*dt):Math.min(DRV.maxF,D.v+DRV.acc*dt);}
  else if(backKey){D.v=D.v>.05?Math.max(0,D.v-DRV.brake*dt):Math.max(-DRV.maxR,D.v-DRV.acc*.6*dt);}
  else D.v*=1-Math.min(1,dt*1.2);
  if(K.Space)D.v*=1-Math.min(1,dt*6);
  const st=(K.KeyA||K.ArrowLeft?1:0)-(K.KeyD||K.ArrowRight?1:0);D.steer=lerp(D.steer,st*DRV.steerMax,Math.min(1,dt*3));
  // bicycle model around the rear axle
  const yaw0=tk.yaw,x0=tk.pos[0],z0=tk.pos[2],cy0=G.chip.yaw;
  const yaw=yaw0+D.v/DRV.wheelbase*Math.tan(D.steer)*dt;const x=x0+Math.sin(yaw)*D.v*dt,z=z0+Math.cos(yaw)*D.v*dt;
  truckSetPose(x,z,yaw);settleTrailer(false);
  // jackknife guard: keep the trailer within ~70° of the truck
  let rel=G.chip.yaw-tk.yaw;while(rel>Math.PI)rel-=2*Math.PI;while(rel<-Math.PI)rel+=2*Math.PI;
  const hitWhat=vehicleBlocked([truckBox(x,z,yaw),chipBox()])||(Math.abs(rel)>1.25?'jackknife':null)||logBlock(dt);
  if(hitWhat){truckSetPose(x0,z0,yaw0);G.chip.yaw=cy0;settleTrailer(false);if(Math.abs(D.v)>1.2){SFX.thud(Math.abs(D.v)*2);if(hitWhat==='earl')omBark("HEY! Watch it, I'm old, not a speed bump!",3000);}D.v=hitWhat==='jackknife'?D.v*.2:-D.v*.15;}
  // Earl shuffles out of the way when the truck comes at him
  {const o=G.om,fw=[Math.sin(tk.yaw)*Math.sign(D.v||1),Math.cos(tk.yaw)*Math.sign(D.v||1)];const dx=o.x-tk.pos[0],dz=o.z-tk.pos[2];const ahead=dx*fw[0]+dz*fw[1],side=dx*fw[1]-dz*fw[0];
    if(Math.abs(D.v)>.3&&ahead>0&&ahead<9&&Math.abs(side)<2.6&&!o.walkTo){const sg=side>=0?1:-1;o.walkTo=[o.x+fw[1]*sg*3.5,o.z-fw[0]*sg*3.5];o.after='idle';
      if(performance.now()-(o.dodgeT||0)>8000){o.dodgeT=performance.now();omBark(['Whoa whoa whoa! Easy with that thing!',"I'm movin', I'm movin'!",'You drive like my late wife. God rest her.'][Math.floor(Math.random()*3)],3000);}}}
  tk.wheel+=D.v*dt/TRUCK.wheelR;
  if(D.eng)D.eng.set(clamp(Math.abs(D.v)/DRV.maxF,0,1)*.85+.15,fwdKey||backKey?.3:0,.5);
  if(Math.abs(D.v)>.5&&Math.random()<dt*Math.abs(D.v)*.8)SFX.step();}
// logs under the wheels: light ones get shoved, heavy ones stop the truck
function logBlock(dt){const tk=G.truck,D=G.drive;const boxes=[truckBox(tk.pos[0],tk.pos[2],tk.yaw),chipBox()];
  for(const b of PHYS.bodies){if(b.mode!=='dyn')continue;if(Math.hypot(b.pos[0]-tk.pos[0],b.pos[2]-tk.pos[2])>b.rad+7)continue;const R=M3.fromQ(b.q);
    for(const lp of b.pts){const p=V.add(b.pos,M3.vec(R,lp));if(p[1]-G.W.H(p[0],p[2])>1.1)continue;
      for(const B of boxes){if(!obbCircle(B,p[0],p[2],.05))continue;
        if(b.m>350&&Math.abs(D.v)>.2)return 'log';
        const fw=[Math.sin(tk.yaw),0,Math.cos(tk.yaw)];wake(b);b.v=V.add(V.mul(fw,D.v*1.1),[0,.6,0]);return null;}}}
  return null;}
function driveCamera(){const D=G.drive,tk=G.truck,tm=truckMatrix();
  if(D.chase){const back=[-Math.sin(tk.yaw+D.lookYaw),0,-Math.cos(tk.yaw+D.lookYaw)];const eye=V.add(V.add(tk.pos,V.mul(back,9)),[0,4.2,0]);eye[1]=Math.max(eye[1],G.W.H(eye[0],eye[2])+1.5);
    return {eye,yaw:tk.yaw+Math.PI+D.lookYaw,pitch:-.3+D.lookPitch,roll:0};}
  return {eye:M.apply(tm,TRUCK.eye),yaw:tk.yaw+Math.PI+D.lookYaw,pitch:D.lookPitch+tk.pitch,roll:-tk.roll*.5};}

/* ---------- limbs that snap under a felled stem ---------- */
function breakUnderLimbs(){const tr=G.tree,b=tr.body;if(!b||!PHYS.bodies.includes(b)||b.sleep||b.mode!=='dyn'||!b.piece.limbs.length)return;const T=tr.T,H=G.W.H;
  for(const id of b.piece.limbs){const L=T.limbs[id];const te=limbSpan(b.piece,id)[1];const tip=bodyWorld(b,limbPt(L,te)),mid=bodyWorld(b,limbPt(L,te*.55)),base=bodyWorld(b,L.base);const dW=Q.rot(b.q,L.dir);
    // any point of the limb or its side branches on the ground
    const pts=[tip,mid,bodyWorld(b,limbPt(L,.3)),...L.subs.filter(sb=>sb.t<=te).map(sb=>{const o=limbPt(L,sb.t);return bodyWorld(b,V.add(o,V.mul(sb.dir,sb.len)));})];
    const tipDown=pts.some(q=>q[1]-H(q[0],q[2])<.22);
    const stemUp=base[1]-H(base[0],base[2])>T.rAt(L.y)+.12;                                   // and the stem is still held up off the ground
    if(tipDown&&(dW[1]<-.15||stemUp)){
      const lb=limbBody(b,id);lb.v=V.add(lb.v,[(Math.random()-.5)*1.5,.8,(Math.random()-.5)*1.5]);lb.w=[(Math.random()-.5)*3,(Math.random()-.5)*3,(Math.random()-.5)*3];
      emit(base,[0,1.5,0],10,hex('#c4ae88'),2,1,.04);if(performance.now()-(G.lastSnap||0)>120){G.lastSnap=performance.now();SFX.crack();}
      return;}}}   // one per frame: the stem body was replaced
