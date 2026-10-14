/* =====================================================================
   Arbor Simulator · physics.js
   A small rigid-body solver built for logs and branches:
   - every body is a cloud of mass samples (gives mass, centre of mass, inertia)
   - contact points on the body's surface collide with the terrain
   - capsules describe the body's shape for body-vs-body contacts and ray casts
   Sequential impulses with friction, fixed sub-steps, sleeping.
   ===================================================================== */
'use strict';

/* ---------- 3x3 helpers (row-major arrays of 9) ---------- */
const M3={
  mul:(a,b)=>{const o=new Array(9);for(let r=0;r<3;r++)for(let c=0;c<3;c++)o[r*3+c]=a[r*3]*b[c]+a[r*3+1]*b[3+c]+a[r*3+2]*b[6+c];return o;},
  T:a=>[a[0],a[3],a[6],a[1],a[4],a[7],a[2],a[5],a[8]],
  vec:(a,v)=>[a[0]*v[0]+a[1]*v[1]+a[2]*v[2],a[3]*v[0]+a[4]*v[1]+a[5]*v[2],a[6]*v[0]+a[7]*v[1]+a[8]*v[2]],
  inv:m=>{const [a,b,c,d,e,f,g,h,i]=m;const A=e*i-f*h,B=-(d*i-f*g),C=d*h-e*g;const det=a*A+b*B+c*C||1e-9;
    return [A/det,-(b*i-c*h)/det,(b*f-c*e)/det,B/det,(a*i-c*g)/det,-(a*f-c*d)/det,C/det,-(a*h-b*g)/det,(a*e-b*d)/det];},
  // rotation matrix (row-major) from quaternion
  fromQ:q=>{const [x,y,z,w]=q;return [1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w), 2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w), 2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)];},
};

const PHYS={g:9.81,dt:1/180,mu:.65,beta:.25,slop:.004,bodies:[],acc:0,onImpact:null};

/* Create a body from mass samples given in an arbitrary "wood frame".
   samples: [{p,m,I}] where I is the sample's own inertia (row-major 3x3) or null
   pts: surface contact points (wood frame); caps: [{a,b,r}] (wood frame)
   q, frameOrigin: orientation and world position of the wood frame's origin */
function makeBody(samples,pts,caps,q,frameOrigin,extra){let m=0;const c=[0,0,0];
  for(const s of samples){m+=s.m;c[0]+=s.p[0]*s.m;c[1]+=s.p[1]*s.m;c[2]+=s.p[2]*s.m;}
  c[0]/=m;c[1]/=m;c[2]/=m;
  const I=[0,0,0,0,0,0,0,0,0];for(const s of samples){const d=V.sub(s.p,c),dd=V.dot(d,d);
    I[0]+=s.m*(dd-d[0]*d[0]);I[4]+=s.m*(dd-d[1]*d[1]);I[8]+=s.m*(dd-d[2]*d[2]);
    I[1]-=s.m*d[0]*d[1];I[2]-=s.m*d[0]*d[2];I[5]-=s.m*d[1]*d[2];if(s.I)for(let k=0;k<9;k++)I[k]+=s.I[k];}
  I[3]=I[1];I[6]=I[2];I[7]=I[5];
  const b=Object.assign({m,im:1/m,Ib:I,iIb:M3.inv(I),com:c,q:q.slice(),v:[0,0,0],w:[0,0,0],
    pts:pts.map(p=>V.sub(p,c)),ptR:pts.map(p=>p[3]||0),caps:caps.map(k=>Object.assign({},k,{a:V.sub(k.a,c),b:V.sub(k.b,c)})),sleep:false,still:0,mode:'dyn'},extra||{});
  b.pos=V.add(frameOrigin,Q.rot(q,c));
  let rad=0;for(const p of b.pts)rad=Math.max(rad,V.len(p));for(const k of b.caps)rad=Math.max(rad,V.len(k.a)+k.r,V.len(k.b)+k.r);b.rad=rad;
  return b;}
// world-space position of a point given in the body's wood frame
function bodyWorld(b,woodP){return V.add(b.pos,Q.rot(b.q,V.sub(woodP,b.com)));}
function bodyLocal(b,worldP){return V.add(Q.rot(Q.conj(b.q),V.sub(worldP,b.pos)),b.com);}
function bodyMatrix(b){return M.mul(M.QT(b.q,b.pos),M.T(-b.com[0],-b.com[1],-b.com[2]));}
function wake(b){if(b){b.sleep=false;b.still=0;}}

function applyImpulse(b,iIw,r,J){b.v[0]+=J[0]*b.im;b.v[1]+=J[1]*b.im;b.v[2]+=J[2]*b.im;const dw=M3.vec(iIw,V.cross(r,J));b.w[0]+=dw[0];b.w[1]+=dw[1];b.w[2]+=dw[2];}
function velAt(b,r){const c=V.cross(b.w,r);return [b.v[0]+c[0],b.v[1]+c[1],b.v[2]+c[2]];}
function closestOnSeg(p,a,b){const ab=V.sub(b,a);const t=clamp(V.dot(V.sub(p,a),ab)/(V.dot(ab,ab)||1e-9),0,1);return [V.add(a,V.mul(ab,t)),t];}

/* ---------- one fixed sub-step ---------- */
function physStep(H,extraColliders){const dt=PHYS.dt,B=PHYS.bodies;
  // cache per-body world data
  for(const b of B){if(b.mode!=='dyn'||b.sleep)continue;b.v[1]-=PHYS.g*dt;
    const R=M3.fromQ(b.q);b._R=R;b._iIw=M3.mul(M3.mul(R,b.iIb),M3.T(R));b._contact=0;}
  for(let it=0;it<2;it++){
    // terrain contacts
    for(const b of B){if(b.mode!=='dyn'||b.sleep)continue;const iIw=b._iIw;
      for(let pi=0;pi<b.pts.length;pi++){const lp=b.pts[pi],pr=b.ptR?b.ptR[pi]:0;const r0=M3.vec(b._R,lp),r=[r0[0],r0[1]-pr,r0[2]],px=b.pos[0]+r[0],py=b.pos[1]+r[1],pz=b.pos[2]+r[2];const gh=H(px,pz),d=gh-py;if(d<-.002)continue;
        const e=.3,n=V.norm([H(px-e,pz)-H(px+e,pz),2*e,H(px,pz-e)-H(px,pz+e)]);
        const vp=velAt(b,r),vn=V.dot(vp,n);const bias=Math.max(0,d-PHYS.slop)*PHYS.beta/dt;if(vn>=bias&&d<=0)continue;
        const rn=V.cross(r,n),k=b.im+V.dot(n,V.cross(M3.vec(iIw,rn),r));let jn=(bias-vn)/k;if(jn<=0)continue;
        if(it===0&&-vn>3&&PHYS.onImpact)PHYS.onImpact(b,-vn,[px,py,pz]);
        applyImpulse(b,iIw,r,V.mul(n,jn));b._contact++;
        const vp2=velAt(b,r),vn2=V.dot(vp2,n),vt=V.sub(vp2,V.mul(n,vn2)),lt=V.len(vt);
        if(lt>1e-5){const t=V.mul(vt,1/lt),rt=V.cross(r,t),kt=b.im+V.dot(t,V.cross(M3.vec(iIw,rt),r));const jt=Math.min(lt/kt,PHYS.mu*jn);applyImpulse(b,iIw,r,V.mul(t,-jt));}}}
    // solid boxes: truck cab, bed floor and walls, chipper body
    if(PHYS.boxes)for(const b of B){if(b.mode!=='dyn'||b.sleep)continue;const iIw=b._iIw;
      for(const bx of PHYS.boxes){if(V.dist(b.pos,bx.c)>b.rad+bx.h[0]+bx.h[1]+bx.h[2])continue;
        // push points out through the face on the side the body's centre is on, so a log can't squeeze through a thin wall
        const dc=V.sub(b.pos,bx.c),lc=[V.dot(dc,bx.ax[0]),V.dot(dc,bx.ax[1]),V.dot(dc,bx.ax[2])];
        for(let pi=0;pi<b.pts.length;pi++){const lp=b.pts[pi],pr=b.ptR?b.ptR[pi]:0;const r=M3.vec(b._R,lp),p=V.add(b.pos,r),d=V.sub(p,bx.c);const l=[V.dot(d,bx.ax[0]),V.dot(d,bx.ax[1]),V.dot(d,bx.ax[2])];
          if(Math.abs(l[0])>bx.h[0]+pr||Math.abs(l[1])>bx.h[1]+pr||Math.abs(l[2])>bx.h[2]+pr)continue;
          let k=0,pen=1e9,sg=1;for(let i=0;i<3;i++){const si=Math.abs(lc[i])>bx.h[i]?Math.sign(lc[i]):(Math.sign(l[i])||1);const qq=bx.h[i]+pr-si*l[i];if(qq<pen){pen=qq;k=i;sg=si;}}const n=V.mul(bx.ax[k],sg);
          const vp=velAt(b,r),vn=V.dot(vp,n),bias=Math.max(0,pen-PHYS.slop)*PHYS.beta/dt;if(vn>=bias)continue;
          const kk=b.im+V.dot(n,V.cross(M3.vec(iIw,V.cross(r,n)),r));const jn=(bias-vn)/kk;if(jn<=0)continue;applyImpulse(b,iIw,r,V.mul(n,jn));b._contact++;
          const vp2=velAt(b,r),vt=V.sub(vp2,V.mul(n,V.dot(vp2,n))),lt=V.len(vt);if(lt>1e-5){const t=V.mul(vt,1/lt),kt=b.im+V.dot(t,V.cross(M3.vec(iIw,V.cross(r,t)),r));applyImpulse(b,iIw,r,V.mul(t,-Math.min(lt/kt,PHYS.mu*jn)));}}}}
    // body vs body (points of A against capsules of B)
    for(let i=0;i<B.length;i++)for(let j=0;j<B.length;j++){if(i===j)continue;const A=B[i],C=B[j];
      if(A.mode==='held'||C.mode==='held'||A.mode==='gone'||C.mode==='gone')continue;
      const aDyn=A.mode==='dyn'&&!A.sleep,cDyn=C.mode==='dyn'&&!C.sleep;if(!aDyn)continue;
      if(V.dist(A.pos,C.pos)>A.rad+C.rad)continue;
      const RA=A._R||M3.fromQ(A.q),RC=C._R||M3.fromQ(C.q),iA=A._iIw||M3.mul(M3.mul(RA,A.iIb),M3.T(RA)),iC=C._iIw||M3.mul(M3.mul(RC,C.iIb),M3.T(RC));
      const capsW=C.caps.map(k=>({a:V.add(C.pos,M3.vec(RC,k.a)),b:V.add(C.pos,M3.vec(RC,k.b)),r:k.r}));
      for(let pi=0;pi<A.pts.length;pi++){const lp=A.pts[pi],prA=A.ptR?A.ptR[pi]:0;const rA=M3.vec(RA,lp),p=V.add(A.pos,rA);
        for(const k of capsW){const [cp]=closestOnSeg(p,k.a,k.b);const dv=V.sub(p,cp),dd=V.len(dv),pen=k.r+prA-dd;if(pen<=0||dd<1e-6)continue;
          const n=V.mul(dv,1/dd),rC=V.sub(cp,C.pos);const dyC=C.mode==='dyn';
          const vr=V.sub(velAt(A,rA),dyC?velAt(C,rC):[0,0,0]),vn=V.dot(vr,n);const bias=Math.max(0,pen-PHYS.slop)*PHYS.beta/dt;if(vn>=bias)continue;
          let k2=A.im+V.dot(n,V.cross(M3.vec(iA,V.cross(rA,n)),rA));if(dyC)k2+=C.im+V.dot(n,V.cross(M3.vec(iC,V.cross(rC,n)),rC));
          const jn=(bias-vn)/k2;if(jn<=0)continue;applyImpulse(A,iA,rA,V.mul(n,jn));if(dyC){if(C.sleep&&jn>2)wake(C);if(!C.sleep)applyImpulse(C,iC,rC,V.mul(n,-jn));}
          A._contact=(A._contact||0)+1;
          const vr2=V.sub(velAt(A,rA),dyC?velAt(C,rC):[0,0,0]),vt=V.sub(vr2,V.mul(n,V.dot(vr2,n))),lt=V.len(vt);
          if(lt>1e-5){const t=V.mul(vt,1/lt);const kt=A.im+V.dot(t,V.cross(M3.vec(iA,V.cross(rA,t)),rA))+(dyC?C.im+V.dot(t,V.cross(M3.vec(iC,V.cross(rC,t)),rC)):0);const jt=Math.min(lt/kt,PHYS.mu*jn);
            applyImpulse(A,iA,rA,V.mul(t,-jt));if(dyC&&!C.sleep)applyImpulse(C,iC,rC,V.mul(t,jt));}}}}
    // static colliders (e.g. the stump): vertical cylinders {x,z,r,y0,y1}
    if(extraColliders)for(const b of B){if(b.mode!=='dyn'||b.sleep)continue;for(const lp of b.pts){const r=M3.vec(b._R,lp),p=V.add(b.pos,r);
      for(const c of extraColliders){if(p[1]<c.y0||p[1]>c.y1)continue;const dx=p[0]-c.x,dz=p[2]-c.z,dd=Math.hypot(dx,dz),pen=c.r-dd;if(pen<=0)continue;
        let n=dd>1e-5?[dx/dd,0,dz/dd]:[1,0,0];const topPen=c.y1-p[1];if(topPen<pen){n=[0,1,0];}const P=Math.min(pen,topPen);
        const vp=velAt(b,r),vn=V.dot(vp,n),bias=Math.max(0,P-PHYS.slop)*PHYS.beta/dt;if(vn>=bias)continue;const k=b.im+V.dot(n,V.cross(M3.vec(b._iIw,V.cross(r,n)),r));const jn=(bias-vn)/k;if(jn>0){applyImpulse(b,b._iIw,r,V.mul(n,jn));b._contact++;}}}}
  }
  // integrate
  for(const b of B){if(b.mode!=='dyn'||b.sleep)continue;
    const ld=b._contact?.6:.02,ad=b._contact?1.6:.08;b.v=V.mul(b.v,1-ld*dt);b.w=V.mul(b.w,1-ad*dt);
    b.pos=V.add(b.pos,V.mul(b.v,dt));const w=b.w,q=b.q;const dq=Q.mul([w[0],w[1],w[2],0],q);b.q=Q.norm([q[0]+dq[0]*.5*dt,q[1]+dq[1]*.5*dt,q[2]+dq[2]*.5*dt,q[3]+dq[3]*.5*dt]);
    if(V.len(b.v)<.06&&V.len(b.w)<.1){b.still+=dt;if(b.still>.7){b.sleep=true;b.v=[0,0,0];b.w=[0,0,0];}}else b.still=0;
    if(b.pos[1]<H(b.pos[0],b.pos[2])-5){b.pos[1]=H(b.pos[0],b.pos[2])+1;b.v=[0,0,0];}}
}
function physUpdate(dtReal,H,extra){PHYS.acc+=Math.min(dtReal,.05);let n=0;while(PHYS.acc>=PHYS.dt&&n<12){physStep(H,extra);PHYS.acc-=PHYS.dt;n++;}}

/* ---------- ray cast against body capsules: returns nearest {b,cap,t,p} ---------- */
function rayCapsule(o,d,maxT,a,b,r){// march-free: closest approach between the ray segment and the capsule axis
  const e=V.add(o,V.mul(d,maxT));const u=V.sub(e,o),v=V.sub(b,a),w0=V.sub(o,a);const A=V.dot(u,u),Bv=V.dot(u,v),C=V.dot(v,v),D=V.dot(u,w0),E=V.dot(v,w0);
  const den=A*C-Bv*Bv;let s=den>1e-9?clamp((Bv*E-C*D)/den,0,1):0,t=C>1e-9?clamp((Bv*s+E)/C,0,1):0;s=A>1e-9?clamp((Bv*t-D)/A,0,1):0;
  const pr=V.add(o,V.mul(u,s)),pc=V.add(a,V.mul(v,t));const dist=V.dist(pr,pc);if(dist>r)return null;
  const back=Math.sqrt(Math.max(0,r*r-dist*dist));const T=Math.max(0,s*maxT-back);return {t:T,axisT:t,p:V.add(o,V.mul(d,T))};}
function rayBodies(o,d,maxT,filter){let best=null;for(const b of PHYS.bodies){if(b.mode==='gone'||b.mode==='held')continue;if(filter&&!filter(b))continue;
  if(V.dist(o,b.pos)>maxT+b.rad)continue;const R=M3.fromQ(b.q);
  b.caps.forEach((k,ci)=>{const a=V.add(b.pos,M3.vec(R,k.a)),c=V.add(b.pos,M3.vec(R,k.b));const h=rayCapsule(o,d,maxT,a,c,k.r);if(h&&(!best||h.t<best.t))best={b,ci,cap:k,...h};});}
  return best;}
